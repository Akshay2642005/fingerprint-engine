const std = @import("std");
const testing = std.testing;
const fingerprint = @import("core").fingerprint;
const hashing = @import("core").hashing;

test "hashFeature Boolean produces 32-byte digest" {
    const val = fingerprint.FeatureValue{ .Boolean = true };
    var digest: [32]u8 = undefined;
    try hashing.hashFeature(val, &digest);
    try testing.expectEqual(@as(usize, 32), digest.len);
    // Not all zeros
    try testing.expect(!std.mem.eql(u8, &digest, &[_]u8{0} ** 32));
}

test "hashFeature Boolean produces deterministic output" {
    const val = fingerprint.FeatureValue{ .Boolean = true };
    var d1: [32]u8 = undefined;
    var d2: [32]u8 = undefined;
    try hashing.hashFeature(val, &d1);
    try hashing.hashFeature(val, &d2);
    try testing.expectEqualSlices(u8, &d1, &d2);
}

test "hashFeature Boolean true and false differ" {
    var d1: [32]u8 = undefined;
    var d2: [32]u8 = undefined;
    try hashing.hashFeature(fingerprint.FeatureValue{ .Boolean = true }, &d1);
    try hashing.hashFeature(fingerprint.FeatureValue{ .Boolean = false }, &d2);
    try testing.expect(!std.mem.eql(u8, &d1, &d2));
}

test "hashFeature Integer produces 32-byte digest" {
    var digest: [32]u8 = undefined;
    try hashing.hashFeature(fingerprint.FeatureValue{ .Integer = 42 }, &digest);
    try testing.expectEqual(@as(usize, 32), digest.len);
}

test "hashFeature String produces 32-byte digest" {
    var digest: [32]u8 = undefined;
    try hashing.hashFeature(fingerprint.FeatureValue{ .String = "Mozilla/5.0" }, &digest);
    try testing.expectEqual(@as(usize, 32), digest.len);
}

test "hashFeature String same content same hash" {
    var d1: [32]u8 = undefined;
    var d2: [32]u8 = undefined;
    try hashing.hashFeature(fingerprint.FeatureValue{ .String = "hello" }, &d1);
    try hashing.hashFeature(fingerprint.FeatureValue{ .String = "hello" }, &d2);
    try testing.expectEqualSlices(u8, &d1, &d2);
}

test "hashFeature String different content different hash" {
    var d1: [32]u8 = undefined;
    var d2: [32]u8 = undefined;
    try hashing.hashFeature(fingerprint.FeatureValue{ .String = "hello" }, &d1);
    try hashing.hashFeature(fingerprint.FeatureValue{ .String = "world" }, &d2);
    try testing.expect(!std.mem.eql(u8, &d1, &d2));
}

test "hashFeature Bytes produces digest" {
    var digest: [32]u8 = undefined;
    try hashing.hashFeature(fingerprint.FeatureValue{ .Bytes = &[_]u8{ 0xDE, 0xAD } }, &digest);
    try testing.expectEqual(@as(usize, 32), digest.len);
}

test "hashFeature StringArray produces consistent digest" {
    var d1: [32]u8 = undefined;
    var d2: [32]u8 = undefined;
    const arr = &[_][]const u8{ "en", "fr" };
    try hashing.hashFeature(fingerprint.FeatureValue{ .StringArray = arr }, &d1);
    try hashing.hashFeature(fingerprint.FeatureValue{ .StringArray = arr }, &d2);
    try testing.expectEqualSlices(u8, &d1, &d2);
}

test "hashFeature different types produce different digests" {
    var d1: [32]u8 = undefined;
    var d2: [32]u8 = undefined;
    try hashing.hashFeature(fingerprint.FeatureValue{ .Boolean = true }, &d1);
    try hashing.hashFeature(fingerprint.FeatureValue{ .Integer = 1 }, &d2);
    try testing.expect(!std.mem.eql(u8, &d1, &d2));
}
