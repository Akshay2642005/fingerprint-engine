const std = @import("std");
const core = @import("core");
const format = @import("../format.zig");
const Request = @import("../request.zig").Request;
const Response = @import("../response.zig").Response;

/// normalize: SignalPackage → normalization warnings. Layout:
///   u16 count | (u8 kind | u16 feature_id)×N
pub fn handle(req: *const Request, res: *Response, scratch: std.mem.Allocator) !void {
    const fp = try format.decode(req, scratch);
    const norm = try core.normalization.normalize(fp, scratch);

    var fbs = std.io.fixedBufferStream(res.payload);
    try format.writeNormalizationWarnings(fbs.writer(), norm);
    res.payload_len = fbs.pos;
}
