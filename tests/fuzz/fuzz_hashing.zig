/// Fuzz testing for hashing — ensures hash functions never crash,
/// produce deterministic output, and handle edge cases.

const std = @import("std");
const testing = std.testing;
const core = @import("core");

const FeatureID = core.features.FeatureID;
const FeatureValue = core.fingerprint.FeatureValue;
const Feature = core.fingerprint.Feature;
const Fingerprint = core.fingerprint.Fingerprint;

fn fuzzHashFeature(_: void, smith: *testing.Smith) anyerror!void {
    var out: [32]u8 = undefined;
    const value = FeatureValue{ .Boolean = smith.boolWeightedWithHash(1, 1, 0) };

    // Must not crash
    core.hashing.hashFeature(value, &out) catch return;

    // Must be deterministic — same input produces same output
    var out2: [32]u8 = undefined;
    core.hashing.hashFeature(value, &out2) catch return;
    try testing.expectEqual(out, out2);
}

test "fuzz: hashFeature with arbitrary values" {
    try testing.fuzz({}, fuzzHashFeature, .{});
}

fn fuzzHashFingerprint(_: void, smith: *testing.Smith) anyerror!void {
    var features: [8]Feature = undefined;
    const count = smith.valueWithHash(u3, 0);
    for (0..count) |i| {
        features[i] = .{
            .id = smith.valueWithHash(FeatureID, @intCast(i)),
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

    var out: [32]u8 = undefined;
    // Must not crash
    core.hashing.hashFingerprint(fp, &out) catch return;
}

test "fuzz: hashFingerprint with arbitrary features" {
    try testing.fuzz({}, fuzzHashFingerprint, .{});
}

fn fuzzHasherIncremental(_: void, smith: *testing.Smith) anyerror!void {
    var features: [4]Feature = undefined;
    const count = smith.valueWithHash(u2, 0);
    for (0..count) |i| {
        features[i] = .{
            .id = smith.valueWithHash(FeatureID, @intCast(i)),
            .value = .{ .Boolean = smith.boolWeightedWithHash(1, 1, @intCast(i)) },
        };
    }

    // Batch hash
    var batch_out: [32]u8 = undefined;
    const fp = Fingerprint{
        .metadata = .{
            .schema_version = 1,
            .sdk_version = "0.1.0",
            .collected_at = 0,
        },
        .features = features[0..count],
    };
    core.hashing.hashFingerprint(fp, &batch_out) catch return;

    // Incremental hash
    var hasher = core.hashing.Hasher.init(1, "0.1.0", 0);
    for (features[0..count]) |f| {
        hasher.add(f.id, f.value) catch return;
    }
    var inc_out: [32]u8 = undefined;
    hasher.final(&inc_out);

    // Results should match
    try testing.expectEqual(batch_out, inc_out);
}

test "fuzz: Hasher incremental matches batch" {
    try testing.fuzz({}, fuzzHasherIncremental, .{});
}
