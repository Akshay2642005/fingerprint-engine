//! Application logging — specs/architecture/logging.md (F-2, slice S3).
//!
//! Leaf module (imports std only): every executable (worker, ingress, the
//! combined `fingerprint` binary, scripts) logs through this module at the
//! leaf edge of the dependency graph. Core algorithms never log — only
//! executables and adapters do.
//!
//! Reference: the TigerBeetle pattern. The executable root declares a
//! `std_options.logFn` (`src/log.zig` exports `logFn`) that routes `std.log`
//! — e.g. the AMQP client's `std.log.scoped(.amqp)` — through one
//! runtime-filtered pipeline, and the module writes UTC-timestamped lines to
//! stderr using a fixed per-line buffer (no heap per message). Levels are
//! filtered at runtime (`shouldLog`), not comptime, so `--log-level` can
//! change without recompiling.
//!
//! Formats:
//!   text: 2026-08-08T12:00:00Z [info] (amqp) message key=value
//!   json: {"ts":"2026-08-08T12:00:00Z","level":"info","scope":"amqp","msg":"..."}
//!
//! story: s3-logging

const std = @import("std");

/// Message severity; `err` is the most severe (0). `shouldLog` emits a
/// message when its level is at or below the configured `level`.
pub const Level = enum(u8) { err, warn, info, debug };

/// First-class log category, rendered `(scope)` in text mode and as the
/// `scope` field in json mode. `std.log` scopes (e.g. `.amqp`) are routed
/// through `logFn` by tag name and need not appear here.
pub const Scope = enum { worker, ingress, amqp, engine, pool, scripts };

/// Output encoding: `text` (greppable, human) or `json` (aggregators).
pub const Format = enum { text, json };

/// Runtime level filter; messages below this level are a no-op (default
/// `.info`: err/warn/info shown, debug hidden).
pub var level: Level = .info;

/// Output encoding (default `text`).
pub var format: Format = .text;

/// Upper bound on a single line; a message that does not fit is dropped
/// (the caller-owned-buffer pattern — no heap per message).
const max_line: usize = 4096;

/// Sets the runtime level and format.
pub fn init(level_: Level, format_: Format) void {
    level = level_;
    format = format_;
}

/// Resolved logger configuration after applying precedence.
pub const Config = struct {
    level: Level = .info,
    format: Format = .text,
};

/// Precedence: CLI > env > default (the option → env → default order the
/// ingress URL uses in build.zig). `cli_level`/`cli_format` come from the
/// arg parsers (already validated); `env_level`/`env_format` from
/// `FPKG_LOG_LEVEL`/`FPKG_LOG_FORMAT` (invalid values are null). Pure.
pub fn resolve(
    cli_level: ?Level,
    cli_format: ?Format,
    env_level: ?Level,
    env_format: ?Format,
) Config {
    return .{
        .level = cli_level orelse (env_level orelse .info),
        .format = cli_format orelse (env_format orelse .text),
    };
}

/// Resolves the effective level and format from the process environment
/// (`FPKG_LOG_LEVEL` / `FPKG_LOG_FORMAT`) plus the parsed CLI flags, then
/// applies them. CLI wins over env, env wins over default; invalid env
/// values fall back to the default.
pub fn initFromEnv(alloc: std.mem.Allocator, cli_level: ?Level, cli_format: ?Format) void {
    const config = resolve(cli_level, cli_format, envLevel(alloc), envFormat(alloc));
    init(config.level, config.format);
}

pub fn parseLevel(value: []const u8) ?Level {
    inline for (std.meta.fields(Level)) |field| {
        if (std.mem.eql(u8, value, field.name)) return @enumFromInt(field.value);
    }
    return null;
}

pub fn parseFormat(value: []const u8) ?Format {
    inline for (std.meta.fields(Format)) |field| {
        if (std.mem.eql(u8, value, field.name)) return @enumFromInt(field.value);
    }
    return null;
}

/// True when a message at `lvl` passes the runtime filter.
pub fn shouldLog(lvl: Level) bool {
    return @intFromEnum(lvl) <= @intFromEnum(level);
}

/// Scope-bounded convenience wrapper (the `std.log.scoped` shape): returns a
/// type with `err`/`warn`/`info`/`debug` that log under one scope.
pub fn of(comptime scope: Scope) type {
    return struct {
        pub fn err(comptime fmt: []const u8, args: anytype) void {
            log(scope, .err, fmt, args);
        }
        pub fn warn(comptime fmt: []const u8, args: anytype) void {
            log(scope, .warn, fmt, args);
        }
        pub fn info(comptime fmt: []const u8, args: anytype) void {
            log(scope, .info, fmt, args);
        }
        pub fn debug(comptime fmt: []const u8, args: anytype) void {
            log(scope, .debug, fmt, args);
        }
    };
}

pub const worker = of(.worker);
pub const ingress = of(.ingress);
pub const amqp = of(.amqp);
pub const engine = of(.engine);
pub const pool = of(.pool);
pub const scripts = of(.scripts);

/// Logs one message under a typed scope, honoring the runtime filter.
pub fn log(scope: Scope, lvl: Level, comptime fmt: []const u8, args: anytype) void {
    if (!shouldLog(lvl)) return;
    emit(@tagName(scope), lvl, fmt, args);
}

/// `std_options.logFn`: routes `std.log` calls (the AMQP client's
/// `std.log.scoped(.amqp)`, etc.) through the same filter and format.
/// Declared as `pub const std_options = std.Options{ .log_level = .debug,
/// .logFn = log.logFn };` in the executable root modules, with the comptime
/// level kept at `.debug` (the TigerBeetle pattern) so the runtime filter in
/// `shouldLog` is the only gate.
pub fn logFn(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime fmt: []const u8,
    args: anytype,
) void {
    const lvl: Level = switch (message_level) {
        .err => .err,
        .warn => .warn,
        .info => .info,
        .debug => .debug,
    };
    if (!shouldLog(lvl)) return;
    emit(@tagName(scope), lvl, fmt, args);
}

/// Renders one line into `out` using the current format and the real clock.
/// The output slice is the written bytes; empty on overflow. Exposed for
/// tests; `emit` uses it internally.
pub fn render(
    scope_name: []const u8,
    lvl: Level,
    comptime fmt: []const u8,
    args: anytype,
    out: []u8,
) []const u8 {
    const now: u64 = std.math.cast(u64, std.time.timestamp()) orelse 0;
    return renderAt(now, scope_name, lvl, fmt, args, out);
}

/// `render` with an injected epoch-second timestamp, so tests are exact.
pub fn renderAt(
    secs: u64,
    scope_name: []const u8,
    lvl: Level,
    comptime fmt: []const u8,
    args: anytype,
    out: []u8,
) []const u8 {
    var stream = std.io.fixedBufferStream(out);
    const w = stream.writer();

    switch (format) {
        .text => {
            writeTimestamp(w, secs) catch return &.{};
            w.print(" [{s}] ({s}) ", .{ levelText(lvl), scope_name }) catch return &.{};
            w.print(fmt ++ "\n", args) catch return &.{};
        },
        .json => {
            // Format the message first, then escape it into the line.
            var msg_buf: [max_line]u8 = undefined;
            var msg_stream = std.io.fixedBufferStream(&msg_buf);
            msg_stream.writer().print(fmt, args) catch return &.{};

            w.writeAll("{\"ts\":\"") catch return &.{};
            writeTimestamp(w, secs) catch return &.{};
            w.writeAll("\",\"level\":\"") catch return &.{};
            w.writeAll(levelText(lvl)) catch return &.{};
            w.writeAll("\",\"scope\":\"") catch return &.{};
            writeJsonEscaped(w, scope_name) catch return &.{};
            w.writeAll("\",\"msg\":\"") catch return &.{};
            writeJsonEscaped(w, msg_stream.getWritten()) catch return &.{};
            w.writeAll("\"}\n") catch return &.{};
        },
    }
    return stream.getWritten();
}

fn emit(scope_name: []const u8, lvl: Level, comptime fmt: []const u8, args: anytype) void {
    var buf: [max_line]u8 = undefined;
    const line = render(scope_name, lvl, fmt, args, &buf);
    if (line.len == 0) return;
    _ = std.io.getStdErr().writeAll(line) catch {};
}

/// UTC ISO-8601 timestamp, e.g. `2026-08-08T12:00:00Z`.
fn writeTimestamp(w: anytype, secs: u64) !void {
    const epoch = std.time.epoch.EpochSeconds{ .secs = secs };
    const epoch_day = epoch.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = epoch.getDaySeconds();
    try w.print("{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
        @as(u32, @intCast(year_day.year)),
        @as(u32, month_day.month.numeric()),
        @as(u32, @intCast(month_day.day_index)) + 1,
        @as(u32, day_seconds.getHoursIntoDay()),
        @as(u32, day_seconds.getMinutesIntoHour()),
        @as(u32, day_seconds.getSecondsIntoMinute()),
    });
}

/// Short level text; matches the `--log-level` flag values.
fn levelText(lvl: Level) []const u8 {
    return switch (lvl) {
        .err => "err",
        .warn => "warn",
        .info => "info",
        .debug => "debug",
    };
}

/// JSON string escaping (quote, backslash, and control characters) — the
/// same rules src/scripts.zig `writeJsonString` uses.
fn writeJsonEscaped(w: anytype, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '"', '\\' => {
                try w.writeByte('\\');
                try w.writeByte(c);
            },
            0x08 => try w.writeAll("\\b"),
            0x0C => try w.writeAll("\\f"),
            '\n' => try w.writeAll("\\n"),
            '\r' => try w.writeAll("\\r"),
            '\t' => try w.writeAll("\\t"),
            else => |cc| {
                if (cc < 0x20) {
                    try w.print("\\u{x:0>4}", .{cc});
                } else {
                    try w.writeByte(cc);
                }
            },
        }
    }
}

fn envLevel(alloc: std.mem.Allocator) ?Level {
    const value = std.process.getEnvVarOwned(alloc, "FPKG_LOG_LEVEL") catch return null;
    defer alloc.free(value);
    return parseLevel(std.mem.trim(u8, value, " \t\r\n"));
}

fn envFormat(alloc: std.mem.Allocator) ?Format {
    const value = std.process.getEnvVarOwned(alloc, "FPKG_LOG_FORMAT") catch return null;
    defer alloc.free(value);
    return parseFormat(std.mem.trim(u8, value, " \t\r\n"));
}
