const std = @import("std");
const features = @import("../features/root.zig");
const fingerprint = @import("../fingerprint/root.zig");

const Feature = fingerprint.Feature;
const Fingerprint = fingerprint.Fingerprint;
const FeatureID = features.FeatureID;
const FeatureType = features.FeatureType;
const Registry = features.Registry;

/// A warning produced when a feature value is outside expected bounds.
pub const BoundWarning = struct {
    feature_id: FeatureID,
    name: []const u8,
    reason: BoundReason,
};

/// The reason a value is out of bounds.
pub const BoundReason = union(enum) {
    integer_out_of_range: struct { min: i64, max: i64, actual: i64 },
    float_out_of_range: struct { min: f64, max: f64, actual: f64 },
    float_not_finite: struct { actual: f64 },
    string_empty,
    string_too_long: struct { max_len: usize, actual_len: usize },
    bytes_empty,
    bytes_too_long: struct { max_len: usize, actual_len: usize },
    array_empty,
    array_too_large: struct { max_count: usize, actual_count: usize },
};

// ──────────────────────────────────────────────
// Per-feature bounds
// ──────────────────────────────────────────────

const IntRange = struct { min: i64, max: i64 };

fn getIntegerRange(id: FeatureID) ?IntRange {
    return switch (id) {
        .HardwareConcurrency => .{ .min = 1, .max = 256 },
        .ScreenWidth => .{ .min = 1, .max = 65536 },
        .ScreenHeight => .{ .min = 1, .max = 65536 },
        .AvailableWidth => .{ .min = 1, .max = 65536 },
        .AvailableHeight => .{ .min = 1, .max = 65536 },
        .ColorDepth => .{ .min = 1, .max = 64 },
        .PixelDepth => .{ .min = 1, .max = 64 },
        .SchemaVersion => .{ .min = 0, .max = 255 },
        .CollectionTimestamp => .{ .min = 0, .max = 9999999999 },
        else => null,
    };
}

const FloatRange = struct { min: f64, max: f64 };

fn getFloatRange(id: FeatureID) ?FloatRange {
    return switch (id) {
        .DevicePixelRatio => .{ .min = 0.1, .max = 10.0 },
        else => null,
    };
}

fn getMaxStringLength(id: FeatureID) ?usize {
    return switch (id) {
        .UserAgent => 512,
        .Platform => 128,
        .Vendor => 128,
        .WebGLVendor => 256,
        .WebGLRenderer => 256,
        .WebGLVersion => 64,
        .CpuClass => 64,
        .OperatingSystem => 128,
        .Locale => 32,
        .Timezone => 64,
        .ConnectionType => 32,
        .NotificationPermission => 16,
        .SDKVersion => 64,
        .Language => 32,
        else => null,
    };
}

fn getMaxBytesLength(id: FeatureID) ?usize {
    return switch (id) {
        .CanvasHash, .WebGLHash, .AudioHash, .FontsHash => 64,
        else => null,
    };
}

fn getMaxArrayCount(id: FeatureID) ?usize {
    return switch (id) {
        .Languages => 32,
        .AudioInputDevices, .AudioOutputDevices, .VideoInputDevices => 64,
        else => null,
    };
}

// ──────────────────────────────────────────────
// Single feature bounds check
// ──────────────────────────────────────────────

/// Checks a single feature's value against known bounds.
/// Returns a slice of warnings (empty = conforming).
/// Caller owns the memory.
pub fn checkBounds(feat: Feature, allocator: std.mem.Allocator) ![]BoundWarning {
    var warnings: std.ArrayList(BoundWarning) = .empty;
    defer warnings.deinit(allocator);

    const def = Registry.get(feat.id);

    switch (feat.value) {
        .Integer => |v| {
            if (getIntegerRange(feat.id)) |range| {
                if (v < range.min or v > range.max) {
                    try warnings.append(allocator, BoundWarning{
                        .feature_id = feat.id,
                        .name = def.name,
                        .reason = .{ .integer_out_of_range = .{
                            .min = range.min,
                            .max = range.max,
                            .actual = v,
                        } },
                    });
                }
            }
        },
        .Float => |v| {
            if (!std.math.isFinite(v)) {
                try warnings.append(allocator, BoundWarning{
                    .feature_id = feat.id,
                    .name = def.name,
                    .reason = .{ .float_not_finite = .{ .actual = v } },
                });
            } else if (getFloatRange(feat.id)) |range| {
                if (v < range.min or v > range.max) {
                    try warnings.append(allocator, BoundWarning{
                        .feature_id = feat.id,
                        .name = def.name,
                        .reason = .{ .float_out_of_range = .{
                            .min = range.min,
                            .max = range.max,
                            .actual = v,
                        } },
                    });
                }
            }
        },
        .String => |v| {
            if (v.len == 0) {
                try warnings.append(allocator, BoundWarning{
                    .feature_id = feat.id,
                    .name = def.name,
                    .reason = .{ .string_empty = @as(void, undefined) },
                });
            } else if (getMaxStringLength(feat.id)) |max_len| {
                if (v.len > max_len) {
                    try warnings.append(allocator, BoundWarning{
                        .feature_id = feat.id,
                        .name = def.name,
                        .reason = .{ .string_too_long = .{
                            .max_len = max_len,
                            .actual_len = v.len,
                        } },
                    });
                }
            }
        },
        .Bytes => |v| {
            if (v.len == 0) {
                try warnings.append(allocator, BoundWarning{
                    .feature_id = feat.id,
                    .name = def.name,
                    .reason = .{ .bytes_empty = @as(void, undefined) },
                });
            } else if (getMaxBytesLength(feat.id)) |max_len| {
                if (v.len > max_len) {
                    try warnings.append(allocator, BoundWarning{
                        .feature_id = feat.id,
                        .name = def.name,
                        .reason = .{ .bytes_too_long = .{
                            .max_len = max_len,
                            .actual_len = v.len,
                        } },
                    });
                }
            }
        },
        .StringArray, .IntegerArray, .FloatArray, .BytesArray => {
            const count = switch (feat.value) {
                .StringArray => |v| v.len,
                .IntegerArray => |v| v.len,
                .FloatArray => |v| v.len,
                .BytesArray => |v| v.len,
                else => unreachable,
            };
            if (count == 0) {
                try warnings.append(allocator, BoundWarning{
                    .feature_id = feat.id,
                    .name = def.name,
                    .reason = .{ .array_empty = @as(void, undefined) },
                });
            } else if (getMaxArrayCount(feat.id)) |max_count| {
                if (count > max_count) {
                    try warnings.append(allocator, BoundWarning{
                        .feature_id = feat.id,
                        .name = def.name,
                        .reason = .{ .array_too_large = .{
                            .max_count = max_count,
                            .actual_count = count,
                        } },
                    });
                }
            }
        },
        .Boolean => {},
    }

    return try warnings.toOwnedSlice(allocator);
}

/// Checks bounds for every feature in a fingerprint.
/// Returns a flat list of all bound warnings detected.
pub fn checkAllBounds(fp: Fingerprint, allocator: std.mem.Allocator) ![]BoundWarning {
    var all_warnings: std.ArrayList(BoundWarning) = .empty;
    defer all_warnings.deinit(allocator);

    for (fp.features) |feat| {
        const warnings = try checkBounds(feat, allocator);
        defer allocator.free(warnings);
        for (warnings) |w| {
            try all_warnings.append(allocator, w);
        }
    }

    return try all_warnings.toOwnedSlice(allocator);
}
