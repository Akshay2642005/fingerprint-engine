const std = @import("std");
const serialization = @import("serialization");
const format = @import("../format.zig");
const Request = @import("../request.zig").Request;
const Response = @import("../response.zig").Response;

/// serialize: SignalPackage → bytes in the requested codec. The input is
/// always the binary v1 package (the only decodable form today); `codec`
/// selects the output format (binary or json).
pub fn handle(req: *const Request, res: *Response, scratch: std.mem.Allocator) !void {
    const fp = try format.decodePayload(req.payload, scratch);

    var fbs = std.io.fixedBufferStream(res.payload);
    const w = fbs.writer();
    switch (req.codec) {
        .binary => try serialization.encode(w, fp),
        .json => try serialization.jsonEncode(w, fp),
        else => return error.InvalidPayload,
    }
    res.payload_len = fbs.pos;
}
