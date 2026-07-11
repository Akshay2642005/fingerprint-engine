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

    server.fingerprint_engine_add_boolean(
        engine,
        @intFromEnum(core.features.FeatureID.CookieEnabled),
        1,
    );

    var digest: [32]u8 = undefined;
    const compute_rc = server.fingerprint_engine_compute(engine, &digest);
    try testing.expectEqual(@as(i32, 0), compute_rc);
}

test "engine add integer feature" {
    const engine = server.fingerprint_engine_create().?;
    defer server.fingerprint_engine_destroy(engine);

    server.fingerprint_engine_add_integer(
        engine,
        @intFromEnum(core.features.FeatureID.HardwareConcurrency),
        8,
    );

    var digest: [32]u8 = undefined;
    const compute_rc = server.fingerprint_engine_compute(engine, &digest);
    try testing.expectEqual(@as(i32, 0), compute_rc);
}

test "engine compute twice produces same digest" {
    const engine = server.fingerprint_engine_create().?;
    defer server.fingerprint_engine_destroy(engine);

    server.fingerprint_engine_add_integer(
        engine,
        @intFromEnum(core.features.FeatureID.ScreenWidth),
        1920,
    );

    var digest1: [32]u8 = undefined;
    _ = server.fingerprint_engine_compute(engine, &digest1);

    var digest2: [32]u8 = undefined;
    _ = server.fingerprint_engine_compute(engine, &digest2);

    try testing.expectEqualSlices(u8, &digest1, &digest2);
}

test "engine with no features still produces digest" {
    const engine = server.fingerprint_engine_create().?;
    defer server.fingerprint_engine_destroy(engine);

    var digest: [32]u8 = undefined;
    const rc = server.fingerprint_engine_compute(engine, &digest);
    try testing.expectEqual(@as(i32, 0), rc);
}

test "engine with string feature" {
    const engine = server.fingerprint_engine_create().?;
    defer server.fingerprint_engine_destroy(engine);

    const ua = "Mozilla/5.0";
    const rc = server.fingerprint_engine_add_string(
        engine,
        @intFromEnum(core.features.FeatureID.UserAgent),
        ua,
        @as(i32, @intCast(ua.len)),
    );
    try testing.expectEqual(@as(i32, 0), rc);

    var digest: [32]u8 = undefined;
    const compute_rc = server.fingerprint_engine_compute(engine, &digest);
    try testing.expectEqual(@as(i32, 0), compute_rc);
}

test "engine normalize returns count" {
    const engine = server.fingerprint_engine_create().?;
    defer server.fingerprint_engine_destroy(engine);

    server.fingerprint_engine_add_boolean(engine, @intFromEnum(core.features.FeatureID.CookieEnabled), 1);
    _ = server.fingerprint_engine_add_string(
        engine,
        @intFromEnum(core.features.FeatureID.UserAgent),
        "test",
        4,
    );

    const warnings = server.fingerprint_engine_normalize(engine);
    try testing.expect(warnings >= 0);
}

test "engine risk returns score" {
    const engine = server.fingerprint_engine_create().?;
    defer server.fingerprint_engine_destroy(engine);

    server.fingerprint_engine_add_boolean(engine, @intFromEnum(core.features.FeatureID.CookieEnabled), 1);
    _ = server.fingerprint_engine_add_string(engine, @intFromEnum(core.features.FeatureID.UserAgent), "Mozilla/5.0", 11);

    const risk = server.fingerprint_engine_risk(engine);
    try testing.expect(risk >= 0 and risk <= 100);
}

test "engine entropy returns score" {
    const engine = server.fingerprint_engine_create().?;
    defer server.fingerprint_engine_destroy(engine);

    server.fingerprint_engine_add_boolean(engine, @intFromEnum(core.features.FeatureID.CookieEnabled), 1);
    _ = server.fingerprint_engine_add_string(engine, @intFromEnum(core.features.FeatureID.UserAgent), "Mozilla/5.0", 11);

    const entropy = server.fingerprint_engine_entropy(engine);
    try testing.expect(entropy >= 0);
}
