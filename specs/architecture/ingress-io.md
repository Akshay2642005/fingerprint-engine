# Ingress io — outbound `connect` + pooled client (S4-a/S4-b)

Slice S4-a/S4-b of the F-1 ingress milestone
(`specs/architecture/ingress.md`), story `s4-ingress-http`. The HTTP
ingress is a TCP **client** to the workers: it opens pooled connections and
exchanges FPKG frames over them. The completion-based io layer
(`src/io/*.zig`, worker-resilience.md S1) has accept/recv/send/timeout/
cancel — but **no outbound `connect`**. This document adds it, plus the
adapter-level pooled client that rides it.

## Why the io layer, not `std.net` threads

S1's conclusion applies unchanged: a deadline must come from the event loop,
not the socket (`SO_RCVTIMEO` is unreliable on Windows once a socket is
non-blocking). The ingress must bound every stage — worker connect, frame
exchange, HTTP reads — on every platform with one code path. Threads per
connection would also break the pool design: each pooled connection is a
long-lived socket owned by the event loop, so a slow worker (or a stuck
HTTP client) must never pin a thread. `connect` joins the existing
`Completion`/`submit`/`flush` contract, so the io_uring design vision for
the Linux backend applies to it like everything else.

## Slice A — `io.connect` (three backends)

New `Completion.Operation.connect` on every backend, racing the same way
`accept`/`recv`/`send` do (submit → `WouldBlock` → kernel owns it →
harvest → callback exactly once; `cancel` completes `error.Canceled`):

| Backend | Pass 1 | Kernel wait | Pass 2 |
|---------|--------|-------------|--------|
| Linux (epoll) | `posix.connect` (non-blocking); `EINPROGRESS` → register `EPOLLOUT` | EPOLLOUT fires on connect completion | `posix.getsockoptError(socket)` — success or the connect error |
| Windows (IOCP) | bind wildcard, load `ConnectEx` via `WSAIoctl(SIO_GET_EXTENSION_FUNCTION_POINTER, WSAID_CONNECTEX)`, start overlapped `ConnectEx` | IOCP delivery (same path as recv/send) | `WSAGetOverlappedResult` — success; error mapped to `posix.ConnectError` |
| Darwin (kqueue) | `posix.connect` (non-blocking); `EINPROGRESS` → queue `EVFILT.WRITE` | EVFILT_WRITE fires on connect completion | `posix.getsockoptError(socket)` |

Cancellation: Linux/Darwin unregister the pending interest and decrement
`io_pending`/`io_inflight`; Windows `CancelIoEx`s the overlapped connect and
balances `io_pending` on the aborted delivery (the existing pattern).

The caller always owns the socket: on any connect failure the io layer
returns the error and leaves the socket open for the caller to close.

`ConnectError` is `posix.ConnectError || error{Canceled}` on every backend
(Windows maps WSA codes onto the same error set; `WSA_OPERATION_ABORTED`
from `CancelIoEx` surfaces `error.Canceled`).

## Slice B — `adapter.TcpClient`

`src/adapter/client.zig`, the ingress's pooled worker client. Mirrors
`adapter/tcp.zig`'s structure (same H-1 race, same slot bookkeeping) but as
an outbound client:

- `init(allocator, host, port, idle_timeout_ns)` — creates the socket.
- `connect(deadline_ns)` — `io.connect` raced against a deadline completion
  (H-1 pattern); success returns the connected socket. `0` waits forever.
- `readFrame(allocator)` / `writeFrame(frame)` — `recvExact`/`send` with
  per-stage deadlines, identical to `Tcp`; zero-payload frames are handled
  (no empty recv — the S1 epoll invariant).
- `close()` — cancels in-flight ops, closes the socket, deinits the io loop.
- Not a `Transport` (it never `accept`s; the worker is the server), but it
  reuses `adapter.buildFrame` / `adapter.decodeFrame` so framing stays
  single-source.

The pool (S4-d) wraps N `TcpClient`s per worker seed and serializes requests
over each connection — the worker serves one client at a time, so a pooled
connection is the concurrency unit.

## Tests

Unit (`tests/io/io_test.zig`):

- `connect` completes when a listener accepts (spawned thread).
- `connect` fails `error.ConnectionRefused` when nothing listens.
- `connect` loses to a deadline (timeout completion wins, connect is
  cancelled — mirroring the adapter race).
- a cancelled `connect` completes exactly once with `error.Canceled`:
  queued-but-never-started ops deliver the synthetic Canceled on the next
  drain (all three backends — Windows gained the `cancelled` short-circuit
  to match), in-flight ops via the kernel abort path.

Unit (`tests/adapter/client_test.zig` — new file, requires
`SNAP_UPDATE=1 zig build test` to re-register):

- `TcpClient` round-trips a frame against a spawned `adapter.Tcp` echo
  server (connect → writeFrame → readFrame → same frame back).
- `readFrame` fails `error.ConnectionTimedOut` on a silent peer after a
  short `idle_timeout_ns`.

The Linux backend runs in CI; Windows runs on the dev box; Darwin is
compile-checked (`zig build ingress -Dtarget=x86_64-macos`).

## Backlog (not this slice)

- S4-c: HTTP/1.1 server on `io.IO` (accept, bounded request parse, boundary
  checks, `/healthz`, graceful shutdown).
- S4-d: worker pool over `TcpClient`, status→HTTP mapping, e2e tests,
  Dockerfile/compose/CI/release surface.
