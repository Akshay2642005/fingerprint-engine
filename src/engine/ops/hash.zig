const std = @import("std");
const core = @import("core");
const format = @import("../format.zig");
const Request = @import("../request.zig").Request;
const Response = @import("../response.zig").Response;

/// hash: SignalPackage (canonicalized) → FingerprintResult. Layout:
///   [32]u8 digest | u16 feature_count | u16 schema_version
/// Features are sorted by FeatureID first so the digest is independent of
/// collection order — same signals, same digest, on any platform.
pub fn handle(req: *const Request, res: *Response, scratch: std.mem.Allocator) !void {
    var fp = try format.decode(req, scratch);
    format.canonicalize(&fp);

    var digest: [32]u8 = undefined;
    core.hashing.hashFingerprintBuffer(fp.features, &digest);

    var fbs = std.io.fixedBufferStream(res.payload);
    const w = fbs.writer();
    try w.writeAll(&digest);
    try w.writeInt(u16, @intCast(fp.features.len), .little);
    try w.writeInt(u16, fp.metadata.schema_version, .little);
    res.payload_len = fbs.pos;
}
