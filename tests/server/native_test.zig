const std = @import("std");
const testing = std.testing;
const core = @import("core");
const server = @import("server");

test "engine create and destroy" {
    const engine = server.fingerprint_engine_create();
    defer server.fingerprint_engine_destroy(engine);
    try testing.expect(engine != null);
}

test "engine add boolean feature and compute" {
    const engine = server.fingerprint_engine_create().?;
    defer server.fingerprint_engine_destroy(engine);

    const rc = server.fingerprint_engine_add_feature(
        engine,
        @intFromEnum(core.features.FeatureID.CookieEnabled),
        @intFromEnum(core.features.FeatureType.Boolean),
        &[_]u8{1},
        1,
    );
    try testing.expectEqual(@as(i32, 0), rc);

    var digest: [32]u8 = undefined;
    var digest_len: i32 = 32;
    const compute_rc = server.fingerprint_engine_compute(engine, &digest, &digest_len);
    try testing.expectEqual(@as(i32, 0), compute_rc);
    try testing.expectEqual(@as(i32, 32), digest_len);
}

test "engine add integer feature" {
    const engine = server.fingerprint_engine_create().?;
    defer server.fingerprint_engine_destroy(engine);

    var value: i64 = 42;
    const rc = server.fingerprint_engine_add_feature(
        engine,
        @intFromEnum(core.features.FeatureID.HardwareConcurrency),
        @intFromEnum(core.features.FeatureType.Integer),
        std.mem.asBytes(&value),
        8,
    );
    try testing.expectEqual(@as(i32, 0), rc);

    var digest: [32]u8 = undefined;
    var digest_len: i32 = 32;
    const compute_rc = server.fingerprint_engine_compute(engine, &digest, &digest_len);
    try testing.expectEqual(@as(i32, 0), compute_rc);
}

test "engine compute twice produces same digest" {
    const engine = server.fingerprint_engine_create().?;
    defer server.fingerprint_engine_destroy(engine);

    var value: i64 = 1920;
    _ = server.fingerprint_engine_add_feature(
        engine,
        @intFromEnum(core.features.FeatureID.ScreenWidth),
        @intFromEnum(core.features.FeatureType.Integer),
        std.mem.asBytes(&value),
        8,
    );

    var digest1: [32]u8 = undefined;
    var len1: i32 = 32;
    _ = server.fingerprint_engine_compute(engine, &digest1, &len1);

    var digest2: [32]u8 = undefined;
    var len2: i32 = 32;
    _ = server.fingerprint_engine_compute(engine, &digest2, &len2);

    try testing.expectEqualSlices(u8, &digest1, &digest2);
}

test "engine with no features still produces digest" {
    const engine = server.fingerprint_engine_create().?;
    defer server.fingerprint_engine_destroy(engine);

    var digest: [32]u8 = undefined;
    var digest_len: i32 = 32;
    const rc = server.fingerprint_engine_compute(engine, &digest, &digest_len);
    try testing.expectEqual(@as(i32, 0), rc);
}

test "engine with string feature" {
    const engine = server.fingerprint_engine_create().?;
    defer server.fingerprint_engine_destroy(engine);

    const ua = "Mozilla/5.0";
    const rc = server.fingerprint_engine_add_feature(
        engine,
        @intFromEnum(core.features.FeatureID.UserAgent),
        @intFromEnum(core.features.FeatureType.String),
        ua,
        @as(i32, @intCast(ua.len)),
    );
    try testing.expectEqual(@as(i32, 0), rc);

    var digest: [32]u8 = undefined;
    var digest_len: i32 = 32;
    const compute_rc = server.fingerprint_engine_compute(engine, &digest, &digest_len);
    try testing.expectEqual(@as(i32, 0), compute_rc);
}
