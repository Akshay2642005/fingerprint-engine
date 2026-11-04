<!-- // story: m8-observability -->

# ADR-015 — `request_id` propagation and correlation

- **Status:** Adopted (2026-11-04)
- **Source:** `src/io/frame.zig`, `src/io/session_context.zig`,
  `src/cmd/ingress/http.zig`, `src/cmd/worker/worker.zig`,
  `src/cmd/worker/collection_event.zig`, `src/adapter/amqp/publisher.zig`,
  `src/log.zig`
- **Extends:** ADR-012 (versioning & compatibility), ADR-013 (event envelope —
  whose field list is **not** changed here), ADR-014 (observability surfaces).
  Does not supersede any of them.

## Context

M8 needs one correlation id that ties an HTTP collection to the worker's log
lines and to the published event, so an operator can answer "what happened to
this request?" without matching timestamps.

What exists today:

- `signal_package_context = 11` carries `[u16 session_len][session_id]
  [i64 ingress_received_at][body]` from the ingress to the worker
  (`src/io/session_context.zig`). It has no room for a correlation id.
- The FPKG frame header's `reserved` field is pinned to zero (R-5) and is not
  available.
- `src/log.zig` emits `Level`/`Scope`/`Format` (text or JSON) but carries no
  request-scoped context.
- The envelope (`collection_event`, ADR-013 §2) is a **frozen, byte-pinned
  field list** with a fixed key order. `schema_version` in the **body** means
  "the SignalPackage schema this collection used", *not* an envelope version;
  the only envelope versioning today is the `fpkg-envelope-version` **AMQP
  header** (`1`). Adding a key to the JSON body would change a frozen document
  without a body-level version to gate on.

That last point is decisive. Adding a key to a frozen contract that has no
version field is precisely the failure mode ADR-012 exists to prevent, so
`request_id` does **not** go into the JSON envelope in this milestone.

## Decision

### 1. New inbound frame type `signal_package_context_v2 = 12`

Append (never renumber — ADR-012 §2) to `MessageType` in `src/io/frame.zig`:

```
payload = [u16 request_id_len][request_id]
          [u16 session_len][session_id]
          [i64 ingress_received_at]
          [signal_package body]
```

- `type 11` **remains accepted and unchanged**. The worker decodes both; a v1
  context simply has no request id.
- Both ids obey the **same validator** as the existing session id: 1–128 bytes
  of `[A-Za-z0-9._:-]` (`session_context.isValidSessionId`). That is what
  makes them safe to log and safe to place in JSON without escaping — the real
  risk here is log injection, not authorization. An empty request id is
  malformed in v2; absence is expressed by using type 11.
- The codec stays in `src/io/session_context.zig` (one implementation shared by
  both sides), so wrapping cannot drift between ingress and worker.
- **The body is untouched.** The digest must remain identical with and without
  a context, which the existing tests already assert for v1; the same property
  is required for v2.

### 2. The ingress mints or honours the id

- If the request carries `x-request-id`, honour it **only** when it passes the
  validator; otherwise mint a fresh 16-byte hex id.
- Always mint when absent. The ingress never forwards a malformed id.
- A counter distinguishes honoured from minted, so an operator can see whether
  their edge actually sends ids.

Honouring a client-supplied id is deliberate: gateways and proxies already mint
these, and correlation across a proxy boundary is the whole point. It is
**never** an authorization input — it only ever reaches logs and message
headers.

### 3. The worker carries it, and emits it as an AMQP message header

- The worker logs `request_id` on every line for that frame and passes it into
  the JSON log context (`src/log.zig`).
- Every published frame carries `request_id` in the **AMQP `headers` table**
  (`BasicProperties.headers`), alongside the existing metadata built by
  `Message.headers()` in `src/adapter/amqp/publisher.zig`. This is additive at
  the AMQP layer and changes no FPKG byte and no envelope key.
- Direct-frame clients (`signal_package`, type 1) have no ingress id; the
  worker mints one for the duration of that frame so logs still correlate.
  Such events publish with a worker-minted id — documented, not silently
  different.

### 4. Persisting it is the platform's migration, not a wire change

Because the header travels with the message, the platform's AMQP consumer can
persist `request_id` at ingest time without the envelope changing. The ledger
contract documents this as a **suggested, platform-owned** nullable column
(`request_id text`) plus a note in `deploy/ledger/README.md`; no engine golden
fixture changes, and no existing consumer breaks.

If a durable envelope field is wanted later, it requires an explicit envelope
version field first — that is a separate ADR.

## Consequences

**Positive**

- End-to-end correlation with zero change to the frozen envelope bytes.
- v1 and v2 contexts coexist; no forced client migration, no flag day.
- The id is validated at the boundary, so it cannot inject into JSON logs.
- The platform gains correlation without a schema migration being imposed on it.

**Negative / costs**

- Two context encodings to maintain (v1 read-only forever, v2 read/write).
- A client-supplied id is attacker-controlled input, even if harmless: it is
  bounded and charset-validated, but it can still be used to correlate two
  requests in an operator's view. Acceptable for logs; never an identity.
- The envelope itself stays un-correlated, so a ledger row's request id depends
  on the platform copying the header. Stated plainly in the ledger README.

**Revisit when:** an envelope version field is introduced in the JSON body
(then `request_id` becomes a first-class envelope field and
`fpkg-envelope-version` advances), or when distributed tracing (W3C
`traceparent`) arrives — that should extend this header rather than add a
parallel mechanism.

## Notes

- Type numbering and the append-only rule: ADR-012 §2.
- Existing context codec and validator: `src/io/session_context.zig`.
- Envelope freeze: ADR-013 §2. Header metadata builder:
  `src/adapter/amqp/publisher.zig` (`Message.headers`).
- Metric for honoured vs minted ids: `fpkg_ingress_request_id_total{source}`
  in `specs/architecture/observability.md`.
