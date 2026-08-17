//! Logging unit tests (specs/architecture/logging.md, S3).
//!
//! Rendering is asserted through `renderAt` with an injected epoch timestamp
//! (epoch 0 = 1970-01-01T00:00:00Z), so the expected lines are exact.

const std = @import("std");
const testing = std.testing;
const log = @import("log");

test "log: parseLevel accepts the four levels and rejects garbage" {
    try testing.expectEqual(log.Level.err, log.parseLevel("err").?);
    try testing.expectEqual(log.Level.warn, log.parseLevel("warn").?);
    try testing.expectEqual(log.Level.info, log.parseLevel("info").?);
    try testing.expectEqual(log.Level.debug, log.parseLevel("debug").?);
    try testing.expect(log.parseLevel("loud") == null);
    try testing.expect(log.parseLevel("") == null);
}

test "log: parseFormat accepts text and json and rejects garbage" {
    try testing.expectEqual(log.Format.text, log.parseFormat("text").?);
    try testing.expectEqual(log.Format.json, log.parseFormat("json").?);
    try testing.expect(log.parseFormat("xml") == null);
}

test "log: shouldLog filters by the runtime level" {
    log.level = .info;
    try testing.expect(log.shouldLog(.err));
    try testing.expect(log.shouldLog(.warn));
    try testing.expect(log.shouldLog(.info));
    try testing.expect(!log.shouldLog(.debug));

    // `--quiet` (amqp get) raises the floor to err: info is silenced.
    log.level = .err;
    try testing.expect(log.shouldLog(.err));
    try testing.expect(!log.shouldLog(.info));

    log.level = .debug;
    try testing.expect(log.shouldLog(.debug));
}

test "log: text render is ts [level] (scope) msg" {
    log.format = .text;
    var out: [256]u8 = undefined;
    const line = log.renderAt(0, "worker", .info, "listening on {s}:{d}", .{
        "127.0.0.1",
        @as(u16, 0),
    }, &out);
    try testing.expectEqualStrings(
        "1970-01-01T00:00:00Z [info] (worker) listening on 127.0.0.1:0\n",
        line,
    );
}

test "log: json render is a single escaped object" {
    log.format = .json;
    var out: [1024]u8 = undefined;
    const line = log.renderAt(0, "amqp", .info, "connection open", .{}, &out);
    try testing.expectEqualStrings(
        "{\"ts\":\"1970-01-01T00:00:00Z\",\"level\":\"info\",\"scope\":\"amqp\",\"msg\":\"connection open\"}\n",
        line,
    );
}

test "log: json render escapes quotes, backslashes, newlines, and control chars" {
    log.format = .json;
    const msg = "he said \"hi\"\\ok\n\t\x01";
    var out: [1024]u8 = undefined;
    const line = log.renderAt(0, "worker", .warn, "msg={s}", .{msg}, &out);
    try testing.expectEqualStrings(
        "{\"ts\":\"1970-01-01T00:00:00Z\",\"level\":\"warn\",\"scope\":\"worker\",\"msg\":\"msg=he said \\\"hi\\\"\\\\ok\\n\\t\\u0001\"}\n",
        line,
    );
}

test "log: scope-bound wrappers compile and are filtered like log()" {
    // With the floor at err, the info/debug wrappers are no-ops (nothing
    // reaches stderr), exercising the scope-bound surface end to end.
    log.level = .err;
    log.format = .text;
    log.of(.worker).info("hidden", .{});
    log.worker.debug("hidden", .{});
    log.ingress.warn("hidden", .{});
    log.amqp.info("hidden", .{});
    log.engine.info("hidden", .{});
    log.pool.info("hidden", .{});
    log.scripts.info("hidden", .{});
    log.logFn(.info, .amqp, "hidden", .{});
}

test "log: resolve — CLI overrides env, env overrides default" {
    const config = log.resolve(null, null, .debug, .json);
    try testing.expectEqual(log.Level.debug, config.level);
    try testing.expectEqual(log.Format.json, config.format);

    const cli_wins = log.resolve(.warn, .text, .debug, .json);
    try testing.expectEqual(log.Level.warn, cli_wins.level);
    try testing.expectEqual(log.Format.text, cli_wins.format);

    const defaults = log.resolve(null, null, null, null);
    try testing.expectEqual(log.Level.info, defaults.level);
    try testing.expectEqual(log.Format.text, defaults.format);
}

test "log: initFromEnv applies the resolved config" {
    const level_before = log.level;
    const format_before = log.format;
    defer log.init(level_before, format_before);

    // No env vars set in the test process: initFromEnv falls back to the
    // defaults, or applies the CLI flags.
    log.initFromEnv(testing.allocator, null, null);
    try testing.expectEqual(log.Level.info, log.level);
    try testing.expectEqual(log.Format.text, log.format);

    log.initFromEnv(testing.allocator, .err, .json);
    try testing.expectEqual(log.Level.err, log.level);
    try testing.expectEqual(log.Format.json, log.format);
}
