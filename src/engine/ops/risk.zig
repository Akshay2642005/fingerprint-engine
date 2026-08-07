const std = @import("std");
const core = @import("core");
const format = @import("../format.zig");
const Request = @import("../request.zig").Request;
const Response = @import("../response.zig").Response;

/// risk: SignalPackage → RiskResult. Layout:
///   f64 score | u8 label_len | label | u8 flag_count | u8× flags
/// Flags are the ordinal values of `core.risk.RiskFlag`.
pub fn handle(req: *const Request, res: *Response, scratch: std.mem.Allocator) !void {
    const fp = try format.decode(req, scratch);
    const assessment = try core.risk.computeRisk(fp, scratch);

    var fbs = std.io.fixedBufferStream(res.payload);
    const w = fbs.writer();
    try w.writeInt(u64, @bitCast(assessment.score), .little);
    try w.writeByte(@intCast(assessment.label.len));
    try w.writeAll(assessment.label);
    try w.writeByte(@intCast(assessment.flags.len));
    for (assessment.flags) |flag| {
        try w.writeByte(@intFromEnum(flag));
    }
    res.payload_len = fbs.pos;
}
