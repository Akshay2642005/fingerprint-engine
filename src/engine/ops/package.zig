const std = @import("std");
const core = @import("core");
const serialization = @import("serialization");
const format = @import("../format.zig");
const Request = @import("../request.zig").Request;
const Response = @import("../response.zig").Response;

/// package: raw collected features → validated, normalized, serialized
/// package. The browser's primary call: one request runs the whole pipeline
/// and returns diagnostics alongside the package. Layout:
///   [validation result block]        (see format.writeValidationResult)
///   u32 package_len | package bytes  (v1 binary encode of the input)
pub fn handle(req: *const Request, res: *Response, scratch: std.mem.Allocator) !void {
    const fp = try format.decode(req, scratch);
    const required = try core.validation.checkRequired(fp, scratch);
    const norm = try core.normalization.normalize(fp, scratch);

    var fbs = std.io.fixedBufferStream(res.payload);
    const w = fbs.writer();
    try format.writeValidationResult(w, required, norm);

    // Re-encode the (normalized) package. The codec is version-field-driven,
    // so a v1 input round-trips as v1 and a v2 input keeps its replay identity.
    const pos_before = fbs.pos;
    try w.writeInt(u32, 0, .little); // placeholder, patched below
    const pkg_start = fbs.pos;
    try serialization.encode(w, fp);
    const pkg_len = fbs.pos - pkg_start;
    std.mem.writeInt(u32, res.payload[pos_before..][0..4], @intCast(pkg_len), .little);

    res.payload_len = fbs.pos;
}
