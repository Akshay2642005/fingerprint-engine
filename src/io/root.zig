//! Async IO primitives (D7) — the transport boundary's substrate.
//!
//! Zero-dependency layer (std only): everything above (serialization,
//! engine, adapter, worker) depends on io, never the reverse.
//!
//! Ownership model: `Message` is arena-backed by its `MessagePool`;
//! `Completion` is embedded and zero-allocation; FPKG frames are
//! encoded/decoded over the fixed-buffer `Reader`/`Writer`.
//!
//! Two completion flavors coexist:
//! - `Completion` (completion.zig) — the user-space deferred callback the
//!   channel parks on; deterministic FIFO, no kernel involvement.
//! - `IO.Completion` (the platform backends) — kernel-backed async
//!   operations (accept/recv/send/timeout/cancel) driven by the event loop
//!   below; the adapter and worker race these against deadline completions
//!   (worker-resilience.md S1).

const builtin = @import("builtin");

/// Completion-based event loop (worker-resilience.md S1): epoll on Linux,
/// IOCP on Windows, kqueue on Darwin. io_uring is the documented design
/// vision for the Linux backend; the Completion/submit/flush contract is
/// identical, so swapping backends is a drop-in change.
pub const IO = switch (builtin.target.os.tag) {
    .linux => @import("linux.zig").IO,
    .windows => @import("windows.zig").IO,
    .macos, .ios, .tvos, .watchos, .visionos => @import("darwin.zig").IO,
    else => @compileError("IO is not supported on this platform"),
};

pub const Completion = @import("completion.zig").Completion;
pub const Reader = @import("reader.zig").Reader;
pub const Writer = @import("writer.zig").Writer;
pub const RingBufferType = @import("ring_buffer.zig").RingBufferType;
pub const ChannelType = @import("channel.zig").ChannelType;
pub const Message = @import("message.zig").Message;
pub const MessagePool = @import("message.zig").MessagePool;
pub const Executor = @import("executor.zig").Executor;
pub const completion_capacity = @import("executor.zig").completion_capacity;
pub const Entry = @import("dispatcher.zig").Entry;
pub const DispatcherType = @import("dispatcher.zig").DispatcherType;
pub const frame = @import("frame.zig");
