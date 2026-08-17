//! Ingress CLI parse tests (ADR-011, S4 scaffold).
//!
//! The CLI surface is real today (parse is pure); the HTTP server lands in
//! S4. These tests pin the argument contract so the standalone `ingress`
//! binary and the combined `fingerprint ingress` subcommand stay
//! byte-compatible.

const std = @import("std");
const testing = std.testing;
const ingress = @import("ingress");
const version_info = @import("version");
const log = @import("log");

test "ingress: version matches the injected build version (BUG-002)" {
    // The CLI must advertise the same version the build injected; a drift
    // here means the version single-source-of-truth was bypassed.
    try testing.expectEqualStrings(version_info.version, ingress.version);
}

test "ingress: parse start requires --listen" {
    try testing.expectError(error.MissingListen, ingress.parse(&.{ "ingress", "start" }));

    const command = try ingress.parse(&.{ "ingress", "start", "--listen=127.0.0.1:8080" });
    switch (command) {
        .start => |options| {
            try testing.expectEqualStrings("127.0.0.1:8080", options.listen.?);
            try testing.expectEqual(ingress.default_max_body, options.max_body);
            try testing.expectEqual(@as(usize, 0), options.worker_count);
            try testing.expect(options.log_level == null);
            try testing.expect(options.log_format == null);
        },
        else => unreachable,
    }
}

test "ingress: parse version and help commands" {
    try testing.expect(try ingress.parse(&.{ "ingress", "version" }) == .version);
    try testing.expect(try ingress.parse(&.{"ingress"}) == .help);
    try testing.expect(try ingress.parse(&.{ "ingress", "--help" }) == .help);
    try testing.expect(try ingress.parse(&.{ "ingress", "-h" }) == .help);
}

test "ingress: parse worker seeds and caps them" {
    const command = try ingress.parse(&.{
        "ingress",
        "start",
        "--listen=127.0.0.1:8080",
        "--worker=127.0.0.1:7001",
        "--worker=127.0.0.1:7002",
    });
    switch (command) {
        .start => |options| {
            try testing.expectEqual(@as(usize, 2), options.worker_count);
            try testing.expectEqualStrings("127.0.0.1:7001", options.workers[0]);
            try testing.expectEqualStrings("127.0.0.1:7002", options.workers[1]);
        },
        else => unreachable,
    }

    // 17 seeds exceeds the fixed-cap CLI buffer (max_workers). The array
    // needs 3 fixed args + (max_workers + 1) worker seeds = max_workers + 4.
    var args: [ingress.max_workers + 4][]const u8 = undefined;
    args[0] = "ingress";
    args[1] = "start";
    args[2] = "--listen=127.0.0.1:8080";
    for (0..ingress.max_workers + 1) |i| {
        args[i + 3] = "--worker=127.0.0.1:7000";
    }
    try testing.expectError(error.TooManyWorkers, ingress.parse(&args));
}

test "ingress: parse overrides body cap and logging" {
    const command = try ingress.parse(&.{
        "ingress",
        "start",
        "--listen=127.0.0.1:8080",
        "--max-body=524288",
        "--log-level=debug",
        "--log-format=json",
    });
    switch (command) {
        .start => |options| {
            try testing.expectEqual(@as(u64, 524288), options.max_body);
            try testing.expectEqual(log.Level.debug, options.log_level.?);
            try testing.expectEqual(log.Format.json, options.log_format.?);
        },
        else => unreachable,
    }
}

test "ingress: parse rejects unknown subcommands, options, and bad values" {
    try testing.expectError(error.UnknownSubcommand, ingress.parse(&.{ "ingress", "bogus" }));
    try testing.expectError(error.UnknownOption, ingress.parse(&.{ "ingress", "start", "--bogus=1" }));
    try testing.expectError(
        error.InvalidOption,
        ingress.parse(&.{ "ingress", "start", "--listen=127.0.0.1:8080", "--max-body=soon" }),
    );
    try testing.expectError(
        error.InvalidOption,
        ingress.parse(&.{ "ingress", "start", "--listen=127.0.0.1:8080", "--log-level=loud" }),
    );
    try testing.expectError(
        error.InvalidOption,
        ingress.parse(&.{ "ingress", "start", "--listen=127.0.0.1:8080", "--log-format=xml" }),
    );
}
