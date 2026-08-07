//! Async IO primitives (D7) — the transport boundary's substrate.
//!
//! Zero-dependency layer (std only): everything above (serialization,
//! engine, adapter, worker) depends on io, never the reverse.
//!
//! Ownership model: `Message` is arena-backed by its `MessagePool`;
//! `Completion` is embedded and zero-allocation; FPKG frames are
//! encoded/decoded over the fixed-buffer `Reader`/`Writer`.

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
