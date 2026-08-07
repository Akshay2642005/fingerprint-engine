const std = @import("std");
const core = @import("core");
const format = @import("../format.zig");
const Request = @import("../request.zig").Request;
const Response = @import("../response.zig").Response;

/// validate: SignalPackage → is_valid flag, missing-required warnings, and
/// normalization warnings. Layout:
///   u8 is_valid
///   u16 required_count | (u16 feature_id | u8 is_critical)×N
///   u16 norm_count     | (u8 kind | u16 feature_id)×N
pub fn handle(req: *const Request, res: *Response, scratch: std.mem.Allocator) !void {
    const fp = try format.decode(req, scratch);
    const required = try core.validation.checkRequired(fp, scratch);
    const norm = try core.normalization.normalize(fp, scratch);

    var fbs = std.io.fixedBufferStream(res.payload);
    try format.writeValidationResult(fbs.writer(), required, norm);
    res.payload_len = fbs.pos;
}
