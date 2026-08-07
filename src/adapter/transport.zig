/// Comptime Transport contract (design §7.1, D16) plus the shared FPKG
/// framing helpers every transport implementation uses.
///
/// A transport moves whole FPKG frames (header + payload, io/frame.zig) —
/// never engine requests. Mapping frames to engine Requests is the worker's
/// job, so transports stay interchangeable: loopback (memory or stdin/stdout
/// pipes), tcp (request/response server), and the future amqp outbound
/// publisher. Adapters own transport concerns; the engine never sees them.
const std = @import("std");
const io = @import("io");

/// Upper bound on a single frame payload (16 MiB). Rejecting oversized
/// payloads at the boundary keeps a corrupt or hostile header from
/// triggering a huge allocation.
pub const max_payload: usize = 16 * 1024 * 1024;

/// Compile-time contract check. A transport type must provide:
///   init(allocator, options) !T           — construct the transport
///   deinit(self: *T) void                 — release owned resources
///   readFrame(self: *T, allocator) ![]const u8 — one inbound FPKG frame;
///                                          memory is owned by the caller
///   writeFrame(self: *T, frame) !void     — send one FPKG frame
///   publish(self: *T, payload) !void      — outbound events; no-op in v1
///   ack(self: *T, frame) void             — poison handling; no-op in v1
/// The worker is generic over any conforming type; this check gives the same
/// guarantee at the type level with a readable error.
pub fn check(comptime T: type) void {
    const required = [_][]const u8{
        "init",       "deinit",  "readFrame",
        "writeFrame", "publish", "ack",
    };
    inline for (required) |name| {
        if (!@hasDecl(T, name)) {
            @compileError("Transport type '" ++ @typeName(T) ++
                "' is missing required method '" ++ name ++ "'");
        }
    }
}

/// Writes a full FPKG frame (header + payload) into `out`, computing the
/// integrity digest from the payload. Returns the written slice.
pub fn buildFrame(
    message_type: io.frame.MessageType,
    codec: io.frame.Codec,
    payload: []const u8,
    out: []u8,
) ![]const u8 {
    if (payload.len > max_payload) return error.PayloadTooLarge;
    const header = io.frame.FrameHeader{
        .message_type = message_type,
        .codec = codec,
        .payload_len = @intCast(payload.len),
        .integrity = io.frame.FrameHeader.integrityOf(payload),
    };

    var w = io.Writer.init(out);
    try header.encode(&w);
    try w.writeBytes(payload);
    return w.written();
}

pub const DecodedFrame = struct {
    header: io.frame.FrameHeader,
    /// Borrows from the input buffer.
    payload: []const u8,
};

/// Parses and validates a full FPKG frame: magic, envelope version, message
/// type/codec tags, and payload integrity.
pub fn decodeFrame(bytes: []const u8) !DecodedFrame {
    if (bytes.len < io.frame.header_size) return error.Truncated;

    var r = io.Reader.init(bytes);
    const header = try io.frame.FrameHeader.decode(&r);
    if (header.payload_len > max_payload) return error.PayloadTooLarge;

    const end = io.frame.header_size + header.payload_len;
    if (end > bytes.len) return error.Truncated;
    const payload = bytes[io.frame.header_size..end];
    if (!io.frame.FrameHeader.integrityValid(header, payload)) return error.IntegrityViolation;

    return .{ .header = header, .payload = payload };
}

/// Reads exactly one FPKG frame from any reader exposing `readNoEof`
/// (std.io.Reader — stream, file, or fixed-buffer readers). The returned
/// frame bytes are allocated from `allocator` and owned by the caller;
/// integrity is validated before returning.
pub fn readFrameFrom(reader: anytype, allocator: std.mem.Allocator) ![]const u8 {
    var header_buf: [io.frame.header_size]u8 = undefined;
    try reader.readNoEof(&header_buf);

    var r = io.Reader.init(&header_buf);
    const header = try io.frame.FrameHeader.decode(&r);
    if (header.payload_len > max_payload) return error.PayloadTooLarge;

    const frame_len = io.frame.header_size + header.payload_len;
    const full = try allocator.alloc(u8, frame_len);
    errdefer allocator.free(full);
    @memcpy(full[0..io.frame.header_size], &header_buf);
    try reader.readNoEof(full[io.frame.header_size..]);

    _ = try decodeFrame(full); // validates integrity
    return full;
}
