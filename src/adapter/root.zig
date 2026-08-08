//! Adapter layer (design §7, D16): transport implementations that move FPKG
//! frames between the worker and the outside world, plus the outbound AMQP
//! client. Depends on io and stdx only — never on engine or serialization, so
//! transports stay interchangeable and the engine stays transport-agnostic.

pub const transport = @import("transport.zig");
pub const Loopback = @import("loopback.zig").Loopback;
pub const Tcp = @import("tcp.zig").Tcp;

/// Outbound AMQP 0.9.1 client (worker → fraud platform / broker).
pub const amqp = @import("amqp/client.zig");

/// Worker result publisher: owns the broker topology (exchange, routing
/// keys, headers) on top of the AMQP client.
pub const amqp_publisher = @import("amqp/publisher.zig");

pub const max_payload = transport.max_payload;
pub const buildFrame = transport.buildFrame;
pub const decodeFrame = transport.decodeFrame;
pub const readFrameFrom = transport.readFrameFrom;
