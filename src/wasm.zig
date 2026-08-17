const std = @import("std");
const core = @import("core");
const model = @import("model");
const version_info = @import("version");

const FeatureID = model.FeatureID;
const FeatureType = model.FeatureType;
const FeatureValue = model.FeatureValue;
const Feature = model.Feature;
const Fingerprint = model.Fingerprint;

const MAX_FEATURES = 128;
const MAX_RAW_DATA = 65536;
const SCRATCH_SIZE = 65536;

/// Error codes returned by exported functions.
pub const ErrorCode = enum(u32) {
    success = 0,
    buffer_full = 1,
    invalid_feature_id = 2,
    invalid_value_type = 3,
    not_initialized = 4,
    invalid_input = 5,
};

// ── Static state ──

var feature_buffer: [MAX_FEATURES]Feature = undefined;
var feature_count: usize = 0;
var initialized: bool = false;
var digest_buffer: [32]u8 = undefined;
var error_message: [256]u8 = undefined;
var error_len: usize = 0;

// Scratch buffer for writing string/bytes data from JavaScript.
// JS writes encoded strings here before passing the pointer to
// fingerprint_add_string / fingerprint_add_bytes.
// The buffer is sized to fit the largest expected feature payload.
var scratch_buffer: [SCRATCH_SIZE]u8 = undefined;

fn setError(comptime fmt: []const u8, args: anytype) void {
    const msg = std.fmt.bufPrint(&error_message, fmt, args) catch unreachable;
    error_len = msg.len;
}

fn addFeature(id: FeatureID, value: FeatureValue) u32 {
    if (!initialized) return @intFromEnum(ErrorCode.not_initialized);
    if (feature_count >= MAX_FEATURES) {
        setError("feature buffer full (max {d})", .{MAX_FEATURES});
        return @intFromEnum(ErrorCode.buffer_full);
    }
    feature_buffer[feature_count] = Feature{ .id = id, .value = value };
    feature_count += 1;
    return @intFromEnum(ErrorCode.success);
}

/// BUG-009: validate a raw u32 feature_id against the FeatureID enum.
fn validateFeatureId(raw_id: u32) ?FeatureID {
    if (raw_id > std.math.maxInt(u16)) return null;
    return std.meta.intToEnum(FeatureID, @as(u16, @intCast(raw_id))) catch null;
}

// ── Core API ──

export fn fingerprint_init() u32 {
    feature_count = 0;
    initialized = true;
    error_len = 0;
    return @intFromEnum(ErrorCode.success);
}

export fn fingerprint_reset() void {
    feature_count = 0;
    error_len = 0;
}

export fn fingerprint_feature_count() u32 {
    return @as(u32, @intCast(feature_count));
}

export fn fingerprint_get_error() u32 {
    if (error_len == 0) return 0;
    error_message[error_len] = 0;
    return @as(u32, @intCast(@intFromPtr(&error_message)));
}

// ── Generic add functions ──

export fn fingerprint_add_boolean(feature_id: u32, value: u32) u32 {
    const id = validateFeatureId(feature_id) orelse return @intFromEnum(ErrorCode.invalid_feature_id);
    return addFeature(id, .{ .Boolean = value != 0 });
}

export fn fingerprint_add_integer(feature_id: u32, value: i64) u32 {
    const id = validateFeatureId(feature_id) orelse return @intFromEnum(ErrorCode.invalid_feature_id);
    return addFeature(id, .{ .Integer = value });
}

export fn fingerprint_add_float(feature_id: u32, value: f64) u32 {
    const id = validateFeatureId(feature_id) orelse return @intFromEnum(ErrorCode.invalid_feature_id);
    return addFeature(id, .{ .Float = value });
}

export fn fingerprint_add_string(feature_id: u32, ptr: u32, len: u32) u32 {
    const id = validateFeatureId(feature_id) orelse return @intFromEnum(ErrorCode.invalid_feature_id);
    const data = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(ptr))));
    // R-8: if the pointer falls inside scratch, copy immediately to avoid
    // aliasing — JS may overwrite scratch before compute reads the value.
    const scratch_start = @intFromPtr(&scratch_buffer);
    const scratch_end = scratch_start + SCRATCH_SIZE;
    const data_ptr = @as(usize, @intCast(ptr));
    if (data_ptr >= scratch_start and data_ptr + len <= scratch_end) {
        const alloc = std.heap.wasm_allocator;
        const buf = alloc.alloc(u8, len) catch return @intFromEnum(ErrorCode.buffer_full);
        @memcpy(buf, data[0..len]);
        return addFeature(id, .{ .String = buf });
    }
    return addFeature(id, .{ .String = data[0..len] });
}

export fn fingerprint_add_bytes(feature_id: u32, ptr: u32, len: u32) u32 {
    const id = validateFeatureId(feature_id) orelse return @intFromEnum(ErrorCode.invalid_feature_id);
    const data = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(ptr))));
    // R-8: same scratch aliasing guard as add_string.
    const scratch_start = @intFromPtr(&scratch_buffer);
    const scratch_end = scratch_start + SCRATCH_SIZE;
    const data_ptr = @as(usize, @intCast(ptr));
    if (data_ptr >= scratch_start and data_ptr + len <= scratch_end) {
        const alloc = std.heap.wasm_allocator;
        const buf = alloc.alloc(u8, len) catch return @intFromEnum(ErrorCode.buffer_full);
        @memcpy(buf, data[0..len]);
        return addFeature(id, .{ .Bytes = buf });
    }
    return addFeature(id, .{ .Bytes = data[0..len] });
}

// ── Compute ──

export fn fingerprint_compute() u32 {
    if (!initialized or feature_count == 0) return 0;

    const features = feature_buffer[0..feature_count];
    std.sort.block(Feature, features, {}, lessThan);

    core.hashing.hashFingerprintBuffer(features, &digest_buffer);
    return @as(u32, @intCast(@intFromPtr(&digest_buffer)));
}

export fn fingerprint_get_digest_ptr() u32 {
    return @as(u32, @intCast(@intFromPtr(&digest_buffer)));
}

/// Returns a pointer to the scratch buffer for writing string/bytes data.
/// The JS wrapper writes encoded data here before passing to add_string/add_bytes.
/// Scratch buffer is 64 KB (SCRATCH_SIZE).
export fn fingerprint_get_scratch_ptr() u32 {
    return @as(u32, @intCast(@intFromPtr(&scratch_buffer)));
}

// ── Processing API ──

export fn fingerprint_normalize() u32 {
    if (!initialized or feature_count == 0) return 0;

    const fp = buildFingerprint();
    const alloc = std.heap.wasm_allocator;

    var count: u32 = 0;
    const type_warns = core.normalization.validateTypes(fp, alloc) catch &.{};
    defer alloc.free(type_warns);
    count += @intCast(type_warns.len);

    const bound_warns = core.normalization.checkAllBounds(fp, alloc) catch &.{};
    defer alloc.free(bound_warns);
    count += @intCast(bound_warns.len);

    return count;
}

export fn fingerprint_risk() f64 {
    if (!initialized or feature_count == 0) return 1.0;
    const fp = buildFingerprint();
    const assessment = core.risk.computeRisk(fp, std.heap.wasm_allocator) catch return 1.0;
    return assessment.score;
}

export fn fingerprint_entropy() f64 {
    if (!initialized or feature_count == 0) return 0.0;
    const fp = buildFingerprint();
    return core.entropy.fingerprintEntropy(fp);
}

// ── Helpers ──

fn buildFingerprint() Fingerprint {
    return .{
        .metadata = .{
            .schema_version = 1,
            .sdk_version = version_info.version,
            .collected_at = 0,
        },
        .features = feature_buffer[0..feature_count],
    };
}

fn lessThan(_: void, a: Feature, b: Feature) bool {
    return @intFromEnum(a.id) < @intFromEnum(b.id);
}
