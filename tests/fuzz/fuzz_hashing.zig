/// Fuzz testing for hashing — ensures hash functions never crash,
/// produce deterministic output, and handle edge cases.
const std = @import("std");
const testing = std.testing;
const core = @import("core");
const model = @import("model");

const FeatureID = model.FeatureID;
const FeatureValue = model.FeatureValue;
const Feature = model.Feature;
const Fingerprint = model.Fingerprint;

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

fn fuzzHashFeature(_: void, input: []const u8) anyerror!void {
    var out: [32]u8 = undefined;
    const value = FeatureValue{ .Boolean = (byteAt(input, 0) & 1) == 1 };

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

fn fuzzHashFingerprint(_: void, input: []const u8) anyerror!void {
    var features: [8]Feature = undefined;
    const count = @min(byteAt(input, 0) & 7, 8);
    for (0..count) |i| {
        features[i] = .{
            .id = randomFeatureID(input, 1 + i),
            .value = .{ .Integer = randomI64(input, 9 + i * 8) },
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

fn fuzzHasherIncremental(_: void, input: []const u8) anyerror!void {
    var features: [4]Feature = undefined;
    const count = byteAt(input, 0) & 3;
    for (0..count) |i| {
        features[i] = .{
            .id = randomFeatureID(input, 1 + i),
            .value = .{ .Boolean = (byteAt(input, 5 + i) & 1) == 1 },
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
