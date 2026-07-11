const std = @import("std");
const core = @import("core");

const FeatureID = core.features.FeatureID;
const FeatureType = core.features.FeatureType;
const FeatureValue = core.fingerprint.FeatureValue;
const Feature = core.fingerprint.Feature;
const Fingerprint = core.fingerprint.Fingerprint;

const MAX_FEATURES = 128;
const MAX_RAW_DATA = 65536;

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
    return addFeature(@enumFromInt(feature_id), .{ .Boolean = value != 0 });
}

export fn fingerprint_add_integer(feature_id: u32, value: i64) u32 {
    return addFeature(@enumFromInt(feature_id), .{ .Integer = value });
}

export fn fingerprint_add_float(feature_id: u32, value: f64) u32 {
    return addFeature(@enumFromInt(feature_id), .{ .Float = value });
}

export fn fingerprint_add_string(feature_id: u32, ptr: u32, len: u32) u32 {
    const data = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(ptr))));
    return addFeature(@enumFromInt(feature_id), .{ .String = data[0..len] });
}

export fn fingerprint_add_bytes(feature_id: u32, ptr: u32, len: u32) u32 {
    const data = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(ptr))));
    return addFeature(@enumFromInt(feature_id), .{ .Bytes = data[0..len] });
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
            .sdk_version = "0.1.0",
            .collected_at = 0,
        },
        .features = feature_buffer[0..feature_count],
    };
}

fn lessThan(_: void, a: Feature, b: Feature) bool {
    return @intFromEnum(a.id) < @intFromEnum(b.id);
}
