const std = @import("std");
const core = @import("core");

const FeatureID = core.features.FeatureID;
const FeatureType = core.features.FeatureType;
const FeatureValue = core.fingerprint.FeatureValue;
const Feature = core.fingerprint.Feature;
const Fingerprint = core.fingerprint.Fingerprint;
const Hasher = core.hashing.Hasher;

const MAX_FEATURES = 64;

/// Error codes returned by exported functions.
pub const ErrorCode = enum(u32) {
    success = 0,
    buffer_full = 1,
    invalid_feature_id = 2,
    invalid_value_type = 3,
    not_initialized = 4,
};

// ── Static state (zero-initialized) ──

/// Feature buffer — stores feature IDs and serialized value bytes.
var feature_buffer: [MAX_FEATURES]Feature = undefined;
var feature_count: usize = 0;
var initialized: bool = false;

// Digest buffer — fixed 32 bytes for SHA-256 output.
var digest_buffer: [32]u8 = undefined;

// Error message buffer.
var error_message: [128]u8 = undefined;
var error_len: usize = 0;

// ── Internal helpers ──

fn setError(comptime fmt: []const u8, args: anytype) void {
    const msg = std.fmt.bufPrint(&error_message, fmt, args) catch unreachable;
    error_len = msg.len;
}

// ── Exported API ──

/// Initializes the fingerprint module.
/// Must be called before any other function.
/// Returns 0 on success, error code on failure.
export fn fingerprint_init() u32 {
    feature_count = 0;
    initialized = true;
    error_len = 0;
    return @intFromEnum(ErrorCode.success);
}

/// Adds a feature to the current fingerprint buffer.
///
/// Parameters:
/// - feature_id: The FeatureID enum value as u32.
/// - value_type: The FeatureType enum value as u32.
/// - value_ptr:  Pointer (in WASM linear memory) to the feature value data.
/// - value_len:  Length of the value data in bytes.
///
/// Returns 0 on success, error code on failure.
export fn fingerprint_add_feature(
    feature_id: u32,
    value_type: u32,
    value_ptr: u32,
    value_len: u32,
) u32 {
    if (!initialized) {
        return @intFromEnum(ErrorCode.not_initialized);
    }

    if (feature_count >= MAX_FEATURES) {
        setError("feature buffer full", .{});
        return @intFromEnum(ErrorCode.buffer_full);
    }

    const id = @as(FeatureID, @enumFromInt(feature_id));

    // Validate FeatureType and deserialize value
    const ftype = @as(FeatureType, @enumFromInt(value_type));
    const data_ptr = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(value_ptr))));
    const data = data_ptr[0..value_len];

    const value = deserializeValue(ftype, data) catch {
        setError("failed to deserialize feature value", .{});
        return @intFromEnum(ErrorCode.invalid_value_type);
    };

    feature_buffer[feature_count] = Feature{
        .id = id,
        .value = value,
    };
    feature_count += 1;

    return @intFromEnum(ErrorCode.success);
}

/// Computes the fingerprint digest (SHA-256) from collected features.
/// Features are sorted by FeatureID before hashing for deterministic output.
/// Returns a pointer to the 32-byte digest in WASM linear memory.
export fn fingerprint_compute() u32 {
    if (!initialized or feature_count == 0) {
        return 0;
    }

    // Sort features by FeatureID
    const features = feature_buffer[0..feature_count];
    std.sort.block(Feature, features, {}, lessThan);

    // Hash fingerprint
    core.hashing.hashFingerprintBuffer(features, &digest_buffer);

    return @as(u32, @intCast(@intFromPtr(&digest_buffer)));
}

/// Returns a pointer to the last computed digest (32 bytes).
export fn fingerprint_get_digest_ptr() u32 {
    return @as(u32, @intCast(@intFromPtr(&digest_buffer)));
}

/// Resets the fingerprint buffer, clearing all collected features.
export fn fingerprint_reset() void {
    feature_count = 0;
    error_len = 0;
}

/// Returns the error message from the last failed operation.
/// Returns a pointer to the error string in WASM linear memory.
export fn fingerprint_get_error() u32 {
    if (error_len == 0) return 0;
    error_message[error_len] = 0;
    return @as(u32, @intCast(@intFromPtr(&error_message)));
}

/// Returns the number of features currently in the buffer.
export fn fingerprint_feature_count() u32 {
    return @as(u32, @intCast(feature_count));
}

// ── Comparison for sorting ──

fn lessThan(_: void, a: Feature, b: Feature) bool {
    return @intFromEnum(a.id) < @intFromEnum(b.id);
}

// ── Value deserialization ──

fn deserializeValue(ftype: FeatureType, data: []const u8) !FeatureValue {
    switch (ftype) {
        .Boolean => {
            if (data.len < 1) return error.InvalidValue;
            return FeatureValue{ .Boolean = data[0] != 0 };
        },
        .Integer => {
            if (data.len < 8) return error.InvalidValue;
            const val = std.mem.readInt(i64, data[0..8], .little);
            return FeatureValue{ .Integer = val };
        },
        .Float => {
            if (data.len < 8) return error.InvalidValue;
            const bits = std.mem.readInt(u64, data[0..8], .little);
            return FeatureValue{ .Float = @bitCast(bits) };
        },
        .String => {
            return FeatureValue{ .String = data };
        },
        .Bytes => {
            return FeatureValue{ .Bytes = data };
        },
        .StringArray => {
            return FeatureValue{ .StringArray = &.{} };
        },
        .IntegerArray => {
            return FeatureValue{ .IntegerArray = &.{} };
        },
        .FloatArray => {
            return FeatureValue{ .FloatArray = &.{} };
        },
        .BytesArray => {
            return FeatureValue{ .BytesArray = &.{} };
        },
    }
}
