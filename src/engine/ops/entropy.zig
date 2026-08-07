const std = @import("std");
const core = @import("core");
const format = @import("../format.zig");
const Request = @import("../request.zig").Request;
const Response = @import("../response.zig").Response;

/// entropy: SignalPackage → entropy score. Layout: f64 (little-endian bits).
pub fn handle(req: *const Request, res: *Response, scratch: std.mem.Allocator) !void {
    const fp = try format.decode(req, scratch);
    const score = core.entropy.fingerprintEntropy(fp);

    var fbs = std.io.fixedBufferStream(res.payload);
    try fbs.writer().writeInt(u64, @bitCast(score), .little);
    res.payload_len = fbs.pos;
}
