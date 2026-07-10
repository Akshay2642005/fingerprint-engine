const std = @import("std");
const testing = std.testing;
const fingerprint = @import("core").fingerprint;
const similarity = @import("core").similarity;

const FV = fingerprint.FeatureValue;

test "Boolean same is 1.0" {
    const a = FV{ .Boolean = true };
    const b = FV{ .Boolean = true };
    const score = similarity.featureScore(a, b);
    try testing.expectEqual(@as(f64, 1.0), score);
}

test "Boolean different is 0.0" {
    const a = FV{ .Boolean = true };
    const b = FV{ .Boolean = false };
    const score = similarity.featureScore(a, b);
    try testing.expectEqual(@as(f64, 0.0), score);
}

test "Integer equal is 1.0" {
    const a = FV{ .Integer = 42 };
    const b = FV{ .Integer = 42 };
    const score = similarity.featureScore(a, b);
    try testing.expectEqual(@as(f64, 1.0), score);
}

test "Integer close is between 0 and 1" {
    const a = FV{ .Integer = 40 };
    const b = FV{ .Integer = 50 };
    const score = similarity.featureScore(a, b);
    try testing.expect(score > 0.0 and score < 1.0);
}

test "Integer far apart is close to 0" {
    const a = FV{ .Integer = 0 };
    const b = FV{ .Integer = 1000000 };
    const score = similarity.featureScore(a, b);
    try testing.expect(score < 0.1);
}

test "Float equal is 1.0" {
    const a = FV{ .Float = 3.14 };
    const b = FV{ .Float = 3.14 };
    const score = similarity.featureScore(a, b);
    try testing.expectEqual(@as(f64, 1.0), score);
}

test "String identical is 1.0" {
    const a = FV{ .String = "hello" };
    const b = FV{ .String = "hello" };
    const score = similarity.featureScore(a, b);
    try testing.expectEqual(@as(f64, 1.0), score);
}

test "String completely different is 0.0" {
    const a = FV{ .String = "abc" };
    const b = FV{ .String = "xyz" };
    const score = similarity.featureScore(a, b);
    try testing.expectEqual(@as(f64, 0.0), score);
}

test "String partially similar is between 0 and 1" {
    const a = FV{ .String = "hello" };
    const b = FV{ .String = "hallo" };
    const score = similarity.featureScore(a, b);
    try testing.expect(score > 0.0 and score < 1.0);
}

test "Bytes identical is 1.0" {
    const a = FV{ .Bytes = &[_]u8{ 0x01, 0x02 } };
    const b = FV{ .Bytes = &[_]u8{ 0x01, 0x02 } };
    const score = similarity.featureScore(a, b);
    try testing.expectEqual(@as(f64, 1.0), score);
}

test "Bytes different is 0.0" {
    const a = FV{ .Bytes = &[_]u8{ 0x01, 0x02 } };
    const b = FV{ .Bytes = &[_]u8{ 0xFF, 0xFE } };
    const score = similarity.featureScore(a, b);
    try testing.expectEqual(@as(f64, 0.0), score);
}

test "StringArray identical is 1.0" {
    const a = FV{ .StringArray = &[_][]const u8{ "en", "fr" } };
    const b = FV{ .StringArray = &[_][]const u8{ "en", "fr" } };
    const score = similarity.featureScore(a, b);
    try testing.expectEqual(@as(f64, 1.0), score);
}

test "StringArray disjoint is 0.0" {
    const a = FV{ .StringArray = &[_][]const u8{ "en" } };
    const b = FV{ .StringArray = &[_][]const u8{ "fr" } };
    const score = similarity.featureScore(a, b);
    try testing.expectEqual(@as(f64, 0.0), score);
}

test "StringArray partly overlapping is between 0 and 1" {
    const a = FV{ .StringArray = &[_][]const u8{ "en", "fr", "de" } };
    const b = FV{ .StringArray = &[_][]const u8{ "en", "fr", "zh" } };
    const score = similarity.featureScore(a, b);
    try testing.expect(score > 0.0 and score < 1.0);
}
