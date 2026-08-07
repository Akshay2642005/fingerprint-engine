/// Fuzz testing for normalization — validates that type checking,
/// bounds checking, and normalize never crash on arbitrary input.
const std = @import("std");
const testing = std.testing;
const core = @import("core");

const FeatureID = core.features.FeatureID;
const FeatureValue = core.fingerprint.FeatureValue;
const Feature = core.fingerprint.Feature;
const Fingerprint = core.fingerprint.Fingerprint;

const ID_COUNT = @typeInfo(FeatureID).@"enum".fields.len;

fn byteAt(input: []const u8, i: usize) u8 {
    return if (i < input.len) input[i] else 0;
}

fn randomFeatureID(input: []const u8, i: usize) FeatureID {
    return @enumFromInt(@as(u16, @intCast(byteAt(input, i) % ID_COUNT)));
}

fn randomI64(input: []const u8, i: usize) i64 {
    var bytes: [8]u8 = .{0} ** 8;
    for (0..8) |j| bytes[j] = byteAt(input, i + j);
    return std.mem.readInt(i64, &bytes, .little);
}

fn fuzzValidateTypes(_: void, input: []const u8) anyerror!void {
    // Generate random features
    var features: [16]Feature = undefined;
    const count = byteAt(input, 0) & 15;
    for (0..count) |i| {
        features[i] = .{
            .id = randomFeatureID(input, 1 + i),
            .value = .{ .Boolean = (byteAt(input, 17 + i) & 1) == 1 },
        };
    }

    const fp = Fingerprint{
        .metadata = .{
            .schema_version = 1,
            .sdk_version = "0.1.0",
            .collected_at = 0,
        },
        .features = features[0..count],
    };

    // Must not crash
    const warnings = core.normalization.validateTypes(fp, std.heap.page_allocator) catch return;
    defer std.heap.page_allocator.free(warnings);
}

test "fuzz: validateTypes handles arbitrary fingerprints" {
    try testing.fuzz({}, fuzzValidateTypes, .{});
}

fn fuzzCheckBounds(_: void, input: []const u8) anyerror!void {
    var features: [4]Feature = undefined;
    const count = byteAt(input, 0) & 3;
    for (0..count) |i| {
        features[i] = .{
            .id = .HardwareConcurrency,
            .value = .{ .Integer = randomI64(input, 1 + i * 8) },
        };
    }

    const fp = Fingerprint{
        .metadata = .{
            .schema_version = 1,
            .sdk_version = "0.1.0",
            .collected_at = 0,
        },
        .features = features[0..count],
    };

    // Must not crash
    const warnings = core.normalization.checkAllBounds(fp, std.heap.page_allocator) catch return;
    defer std.heap.page_allocator.free(warnings);
}

test "fuzz: checkBounds handles arbitrary integers" {
    try testing.fuzz({}, fuzzCheckBounds, .{});
}

fn fuzzNormalize(_: void, input: []const u8) anyerror!void {
    var features: [8]Feature = undefined;
    const count = byteAt(input, 0) & 7;
    for (0..count) |i| {
        features[i] = .{
            .id = randomFeatureID(input, 1 + i),
            .value = .{ .String = "test" },
        };
    }

    const fp = Fingerprint{
        .metadata = .{
            .schema_version = 1,
            .sdk_version = "0.1.0",
            .collected_at = 0,
        },
        .features = features[0..count],
    };

    // Must not crash
    const warnings = core.normalization.normalize(fp, std.heap.page_allocator) catch return;
    defer std.heap.page_allocator.free(warnings);
}

test "fuzz: normalize handles arbitrary data" {
    try testing.fuzz({}, fuzzNormalize, .{});
}
