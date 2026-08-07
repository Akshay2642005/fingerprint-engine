const std = @import("std");
const core = @import("core");
const model = @import("model");
const format = @import("../format.zig");
const Request = @import("../request.zig").Request;
const Response = @import("../response.zig").Response;

/// similarity: dual payload (a, b) → SimilarityResult. Input layout:
///   u32 a_len | a bytes | b bytes
/// Output layout: f64 score | u16 compared_count.
pub fn handle(req: *const Request, res: *Response, scratch: std.mem.Allocator) !void {
    if (req.payload.len < 4) return error.InvalidPayload;
    const a_len = std.mem.readInt(u32, payloadLenBytes(req.payload[0..4]), .little);
    if (req.payload.len < 4 + a_len) return error.InvalidPayload;

    const a = try format.decodePayload(req.payload[4 .. 4 + a_len], scratch);
    const b = try format.decodePayload(req.payload[4 + a_len ..], scratch);

    const score = core.similarity.fingerprintScore(a, b);
    const compared = countCompared(a, b);

    var fbs = std.io.fixedBufferStream(res.payload);
    const w = fbs.writer();
    try w.writeInt(u64, @bitCast(score), .little);
    try w.writeInt(u16, compared, .little);
    res.payload_len = fbs.pos;
}

fn payloadLenBytes(bytes: []const u8) *const [4]u8 {
    return bytes[0..4];
}

fn countCompared(a: model.Fingerprint, b: model.Fingerprint) u16 {
    var count: u16 = 0;
    for (a.features) |fa| {
        for (b.features) |fb| {
            if (fa.id == fb.id) {
                count += 1;
                break;
            }
        }
    }
    return count;
}
