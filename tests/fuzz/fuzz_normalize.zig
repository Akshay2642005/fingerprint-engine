/// Fuzz testing for normalization — validates that type checking,
/// bounds checking, and normalize never crash on arbitrary input.

const std = @import("std");
const testing = std.testing;
const core = @import("core");

const FeatureID = core.features.FeatureID;
const FeatureValue = core.fingerprint.FeatureValue;
const Feature = core.fingerprint.Feature;
const Fingerprint = core.fingerprint.Fingerprint;

fn fuzzValidateTypes(_: void, smith: *testing.Smith) anyerror!void {
    // Generate random features
    var features: [16]Feature = undefined;
    const count = smith.valueWithHash(u4, 0);
    for (0..count) |i| {
        const id = smith.valueWithHash(FeatureID, @intCast(i));
        features[i] = .{
            .id = id,
            .value = .{ .Boolean = smith.boolWeightedWithHash(1, 1, @intCast(i)) },
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

fn fuzzCheckBounds(_: void, smith: *testing.Smith) anyerror!void {
    var features: [4]Feature = undefined;
    const count = smith.valueWithHash(u2, 0);
    for (0..count) |i| {
        features[i] = .{
            .id = .HardwareConcurrency,
            .value = .{ .Integer = smith.valueWithHash(i64, @intCast(i)) },
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

fn fuzzNormalize(_: void, smith: *testing.Smith) anyerror!void {
    var features: [8]Feature = undefined;
    const count = smith.valueWithHash(u3, 0);
    for (0..count) |i| {
        features[i] = .{
            .id = smith.valueWithHash(FeatureID, @intCast(i)),
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
