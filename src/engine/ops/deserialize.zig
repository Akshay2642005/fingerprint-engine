const std = @import("std");
const serialization = @import("serialization");
const format = @import("../format.zig");
const Request = @import("../request.zig").Request;
const Response = @import("../response.zig").Response;

/// deserialize: bytes → model, re-encoded in the same codec. Binary input
/// round-trips through the codec and is re-emitted canonically. JSON decode
/// is not available until the serialization rewrite (v2 body + json decode).
pub fn handle(req: *const Request, res: *Response, scratch: std.mem.Allocator) !void {
    switch (req.codec) {
        .binary => {
            const fp = try format.decodePayload(req.payload, scratch);
            var fbs = std.io.fixedBufferStream(res.payload);
            try serialization.encode(fbs.writer(), fp);
            res.payload_len = fbs.pos;
        },
        else => return error.InvalidPayload,
    }
}
