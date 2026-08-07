//! Adapter layer (design §7, D16): transport implementations that move FPKG
//! frames between the worker and the outside world. Depends on io only —
//! never on engine or serialization, so transports stay interchangeable and
//! the engine stays transport-agnostic.

pub const transport = @import("transport.zig");
pub const Loopback = @import("loopback.zig").Loopback;
pub const Tcp = @import("tcp.zig").Tcp;

pub const max_payload = transport.max_payload;
pub const buildFrame = transport.buildFrame;
pub const decodeFrame = transport.decodeFrame;
pub const readFrameFrom = transport.readFrameFrom;
