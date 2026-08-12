//! Integration and end-to-end tests for Fingerprint Engine.
//!
//! The test binary itself contains no engine code: everything is driven
//! through pre-built executables (`fingerprint-bench`, `scripts`) spawned as
//! subprocesses, with stdout/stderr and exit status asserted.
//!
//! Executable paths are injected at build time by build.zig (test_options),
//! so `zig build test-integration` always exercises the binaries it built.
//! Worker e2e tests spawn the worker and speak the FPKG wire protocol from
//! this binary (which still imports no engine code — framing is duplicated
//! here on purpose, exactly as an external client would).
const std = @import("std");
const builtin = @import("builtin");

const Shell = @import("testing/shell.zig");

const bench_exe: []const u8 = @import("test_options").bench_exe;
const scripts_exe: []const u8 = @import("test_options").scripts_exe;
const worker_exe: []const u8 = @import("test_options").worker_exe;
const ingress_exe: []const u8 = @import("test_options").ingress_exe;
const fingerprint_exe: []const u8 = @import("test_options").fingerprint_exe;

test "scripts: no arguments prints usage and exits 0" {
    const shell = try Shell.create(std.testing.allocator);
    defer shell.destroy();

    const result = try shell.exec(&.{scripts_exe}, .{});
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Usage:") != null);
}

test "scripts: --help prints usage and exits 0" {
    const shell = try Shell.create(std.testing.allocator);
    defer shell.destroy();

    const result = try shell.exec(&.{ scripts_exe, "--help" }, .{});
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Usage:") != null);
}

test "scripts: unknown subcommand prints diagnostics and exits 1" {
    const shell = try Shell.create(std.testing.allocator);
    defer shell.destroy();

    const result = try shell.exec(&.{ scripts_exe, "bogus" }, .{ .expected_exit_code = 1 });
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "unknown subcommand 'bogus'") != null);
}

test "bench: fingerprint-bench runs every benchmark and reports a total" {
    const shell = try Shell.create(std.testing.allocator);
    defer shell.destroy();

    const result = try shell.exec(&.{bench_exe}, .{});
    // Output contract: the bench prints to stderr (std.debug.print). Spot-check
    // the completion line and the first/last benchmark rows; bump the expected
    // count in the same commit that changes the benchmark table.
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "Completed 12 benchmarks.") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "hashing: hashFeature") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "entropy: fingerprintEntropy") != null);
}

// ── Combined CLI e2e (ADR-011) ───────────────────────────────────────

test "fingerprint: version prints the product version and exits 0" {
    const shell = try Shell.create(std.testing.allocator);
    defer shell.destroy();

    const result = try shell.exec(&.{ fingerprint_exe, "version" }, .{});
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "fingerprint version ") != null);
}

test "fingerprint: help prints the combined usage and exits 0" {
    const shell = try Shell.create(std.testing.allocator);
    defer shell.destroy();

    const result = try shell.exec(&.{ fingerprint_exe, "help" }, .{});
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "fingerprint worker start") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "fingerprint ingress start") != null);
}

test "fingerprint: dispatches to the worker subcommand" {
    const shell = try Shell.create(std.testing.allocator);
    defer shell.destroy();

    // The combined binary must stay byte-compatible with the standalone
    // worker CLI (ADR-011 argv contract): `fingerprint worker version` is
    // the same command as `worker version`.
    const result = try shell.exec(&.{ fingerprint_exe, "worker", "version" }, .{});
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "worker version ") != null);
}

test "fingerprint: unknown subcommand prints diagnostics and exits 1" {
    const shell = try Shell.create(std.testing.allocator);
    defer shell.destroy();

    const result = try shell.exec(&.{ fingerprint_exe, "bogus" }, .{ .expected_exit_code = 1 });
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "unknown subcommand 'bogus'") != null);
}

test "ingress: version prints and exits 0" {
    const shell = try Shell.create(std.testing.allocator);
    defer shell.destroy();

    const result = try shell.exec(&.{ ingress_exe, "version" }, .{});
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "ingress version ") != null);
}

test "ingress: missing --listen prints diagnostics and exits 1" {
    const shell = try Shell.create(std.testing.allocator);
    defer shell.destroy();

    const result = try shell.exec(&.{ ingress_exe, "start" }, .{ .expected_exit_code = 1 });
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "requires --listen") != null);
}

// ── Worker e2e ────────────────────────────────────────────────────────

/// Canonical digest of tests/fixtures/fingerprints/signal-package-v2.bin,
/// the fixture `zig build scripts -- generate fixture signal-package-v2`
/// writes. Bump it in the same commit that changes the fixture generator.
const expected_digest = [32]u8{
    0xdb, 0x29, 0xfc, 0x13, 0xd8, 0xda, 0xd5, 0xdc,
    0x0b, 0xd7, 0xb1, 0xf9, 0x97, 0x15, 0x5c, 0xff,
    0x41, 0x1f, 0x3d, 0xa8, 0x8a, 0x59, 0x76, 0x19,
    0xf5, 0xe0, 0xd6, 0x7a, 0x25, 0x1e, 0x6c, 0x75,
};

/// FPKG wire layout (io/frame.zig) as an external client sees it: magic,
/// little-endian version / message_type / codec / payload_len / reserved,
/// then the SHA-256 integrity of the payload. Duplicated here on purpose so
/// this binary exercises the wire protocol instead of shared framing code.
const header_size = 48;
const signal_package_type: u8 = 1;
const fingerprint_result_type: u8 = 4;
const binary_codec: u8 = 1;

fn buildFrame(message_type: u8, payload: []const u8, buf: []u8) ![]const u8 {
    const total = header_size + payload.len;
    if (total > buf.len) return error.FrameTooLarge;
    @memcpy(buf[0..4], "FPKG");
    std.mem.writeInt(u16, buf[4..6], 1, .little); // envelope version
    buf[6] = message_type;
    buf[7] = binary_codec;
    std.mem.writeInt(u32, buf[8..12], @intCast(payload.len), .little);
    std.mem.writeInt(u32, buf[12..16], 0, .little);
    std.crypto.hash.sha2.Sha256.hash(payload, buf[16..48], .{});
    @memcpy(buf[header_size..total], payload);
    return buf[0..total];
}

/// Reads one FPKG frame from `reader` into `buf`, validating nothing but the
/// length (a real client checks integrity; the worker replies are trusted
/// here because the loopback and tcp tests cross-check the same digest).
fn readFrame(reader: anytype, buf: []u8) ![]const u8 {
    var header: [header_size]u8 = undefined;
    try reader.readNoEof(&header);
    const payload_len = std.mem.readInt(u32, header[8..12], .little);
    const total = header_size + payload_len;
    if (total > buf.len) return error.FrameTooLarge;
    @memcpy(buf[0..header_size], &header);
    try reader.readNoEof(buf[header_size..total]);
    return buf[0..total];
}

/// Asserts the reply frame carries `status ok | digest | 3 features | v2`.
fn expectHashReply(reply: []const u8) !void {
    try std.testing.expectEqual(@as(u8, fingerprint_result_type), reply[6]);
    const payload = reply[header_size..];
    try std.testing.expectEqual(@as(u8, 0), payload[0]); // engine.Status.ok
    try std.testing.expectEqualSlices(u8, &expected_digest, payload[1..33]);
    try std.testing.expectEqual(@as(u16, 3), std.mem.readInt(u16, payload[33..35], .little));
    try std.testing.expectEqual(@as(u16, 2), std.mem.readInt(u16, payload[35..37], .little));
}

test "worker: hashes a signal package over the loopback pipe" {
    const shell = try Shell.create(std.testing.allocator);
    defer shell.destroy();

    const fixture = try std.fs.cwd().readFileAlloc(
        std.testing.allocator,
        "tests/fixtures/fingerprints/signal-package-v2.bin",
        1 << 16,
    );
    defer std.testing.allocator.free(fixture);

    var frame_buf: [header_size + 1 << 16]u8 = undefined;
    const frame = try buildFrame(signal_package_type, fixture, &frame_buf);

    const result = try shell.exec(&.{ worker_exe, "start", "--transport=loopback" }, .{ .stdin = frame });
    var fbs = std.io.fixedBufferStream(result.stdout);
    var reply_buf: [header_size + 1 << 16]u8 = undefined;
    try expectHashReply(try readFrame(fbs.reader(), &reply_buf));
}

test "worker: serves fpkf requests over tcp" {
    const alloc = std.testing.allocator;

    var child = std.process.Child.init(
        &.{ worker_exe, "start", "--transport=tcp", "--listen=127.0.0.1:0" },
        alloc,
    );
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    try child.spawn();
    defer {
        _ = child.kill() catch {};
        _ = child.wait() catch {};
    }

    // The worker announces its bound port on stderr (--listen=...:0).
    const stderr_reader = child.stderr.?.reader();
    const port = blk: {
        var announce_buf: [256]u8 = undefined;
        while (true) {
            const line = (try stderr_reader.readUntilDelimiterOrEof(&announce_buf, '\n')) orelse
                return error.WorkerNeverListened;
            if (std.mem.indexOf(u8, line, "worker: listening on ")) |idx| {
                const rest = line[idx + "worker: listening on ".len ..];
                const colon = std.mem.lastIndexOfScalar(u8, rest, ':') orelse
                    return error.MalformedAnnouncement;
                break :blk try std.fmt.parseInt(u16, rest[colon + 1 ..], 10);
            }
        }
    };

    const fixture = try std.fs.cwd().readFileAlloc(alloc, "tests/fixtures/fingerprints/signal-package-v2.bin", 1 << 16);
    defer alloc.free(fixture);

    var frame_buf: [header_size + 1 << 16]u8 = undefined;
    const frame = try buildFrame(signal_package_type, fixture, &frame_buf);

    var stream = try std.net.tcpConnectToHost(alloc, "127.0.0.1", port);
    defer stream.close();
    try stream.writeAll(frame);

    var reply_buf: [header_size + 1 << 16]u8 = undefined;
    try expectHashReply(try readFrame(stream.reader(), &reply_buf));
}

test "worker: survives a protocol-violating tcp client" {
    const alloc = std.testing.allocator;

    var child = std.process.Child.init(
        &.{ worker_exe, "start", "--transport=tcp", "--listen=127.0.0.1:0" },
        alloc,
    );
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    try child.spawn();
    defer {
        _ = child.kill() catch {};
        _ = child.wait() catch {};
    }

    // The worker announces its bound port on stderr (--listen=...:0).
    const stderr_reader = child.stderr.?.reader();
    const port = blk: {
        var announce_buf: [256]u8 = undefined;
        while (true) {
            const line = (try stderr_reader.readUntilDelimiterOrEof(&announce_buf, '\n')) orelse
                return error.WorkerNeverListened;
            if (std.mem.indexOf(u8, line, "worker: listening on ")) |idx| {
                const rest = line[idx + "worker: listening on ".len ..];
                const colon = std.mem.lastIndexOfScalar(u8, rest, ':') orelse
                    return error.MalformedAnnouncement;
                break :blk try std.fmt.parseInt(u16, rest[colon + 1 ..], 10);
            }
        }
    };

    // 1. A client that speaks garbage (e.g. an HTTP probe) is dropped
    //    without killing the worker. Send more bytes than one FPKG header so
    //    the header read completes and the magic check fails. Read until EOF
    //    or an error — either means the server closed the connection.
    var bad = try std.net.tcpConnectToHost(alloc, "127.0.0.1", port);
    defer bad.close();
    const garbage = [_]u8{'G'} ** 256;
    try bad.writeAll(&garbage);
    var sink: [64]u8 = undefined;
    _ = bad.read(&sink) catch {};

    // 2. A well-behaved client is still served on a fresh connection.
    const fixture = try std.fs.cwd().readFileAlloc(alloc, "tests/fixtures/fingerprints/signal-package-v2.bin", 1 << 16);
    defer alloc.free(fixture);

    var frame_buf: [header_size + 1 << 16]u8 = undefined;
    const frame = try buildFrame(signal_package_type, fixture, &frame_buf);

    var stream = try std.net.tcpConnectToHost(alloc, "127.0.0.1", port);
    defer stream.close();
    try stream.writeAll(frame);

    var reply_buf: [header_size + 1 << 16]u8 = undefined;
    try expectHashReply(try readFrame(stream.reader(), &reply_buf));
}

/// Spawns a tcp worker and reads its `worker: listening on host:port`
/// announcement from stderr, returning the bound port.
fn spawnWorker(args: []const []const u8, alloc: std.mem.Allocator) !struct {
    child: std.process.Child,
    port: u16,
} {
    var child = std.process.Child.init(args, alloc);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    try child.spawn();

    const stderr_reader = child.stderr.?.reader();
    var announce_buf: [256]u8 = undefined;
    while (true) {
        const line = (try stderr_reader.readUntilDelimiterOrEof(&announce_buf, '\n')) orelse
            return error.WorkerNeverListened;
        if (std.mem.indexOf(u8, line, "worker: listening on ")) |idx| {
            const rest = line[idx + "worker: listening on ".len ..];
            const colon = std.mem.lastIndexOfScalar(u8, rest, ':') orelse
                return error.MalformedAnnouncement;
            const port = try std.fmt.parseInt(u16, rest[colon + 1 ..], 10);
            return .{ .child = child, .port = port };
        }
    }
}

test "worker: closes an idle tcp client and keeps serving (H-1)" {
    const alloc = std.testing.allocator;

    var spawned = try spawnWorker(&.{
        worker_exe,
        "start",
        "--transport=tcp",
        "--listen=127.0.0.1:0",
        "--idle-timeout-ms=500",
    }, alloc);
    defer {
        _ = spawned.child.kill() catch {};
        _ = spawned.child.wait() catch {};
    }

    // Client A connects and sends nothing; the worker must close it after
    // the 500ms idle deadline instead of wedging the accept loop.
    var idle = try std.net.tcpConnectToHost(alloc, "127.0.0.1", spawned.port);
    defer idle.close();

    std.time.sleep(1500 * std.time.ns_per_ms);

    // The idle client observes EOF (or a reset) — the worker dropped it.
    var sink: [64]u8 = undefined;
    const n = idle.read(&sink) catch 0;
    try std.testing.expectEqual(@as(usize, 0), n);

    // Client B is still served with the pinned digest: the accept loop was
    // not wedged.
    const fixture = try std.fs.cwd().readFileAlloc(
        alloc,
        "tests/fixtures/fingerprints/signal-package-v2.bin",
        1 << 16,
    );
    defer alloc.free(fixture);

    var frame_buf: [header_size + 1 << 16]u8 = undefined;
    const frame = try buildFrame(signal_package_type, fixture, &frame_buf);

    var stream = try std.net.tcpConnectToHost(alloc, "127.0.0.1", spawned.port);
    defer stream.close();
    try stream.writeAll(frame);

    var reply_buf: [header_size + 1 << 16]u8 = undefined;
    try expectHashReply(try readFrame(stream.reader(), &reply_buf));
}

test "worker: exits 0 on SIGTERM after draining (H-2)" {
    // Signal handling is POSIX-only today (worker-resilience.md); Windows
    // relies on SetConsoleCtrlHandler, which e2e tests cannot send.
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const alloc = std.testing.allocator;

    var spawned = try spawnWorker(&.{
        worker_exe,
        "start",
        "--transport=tcp",
        "--listen=127.0.0.1:0",
        // Keep the read deadline short so the drain after SIGTERM is
        // bounded (an idle readFrame cannot stall the exit).
        "--idle-timeout-ms=500",
    }, alloc);
    defer _ = spawned.child.kill() catch {};

    // Exchange one frame so the in-flight path is exercised before the
    // shutdown signal.
    const fixture = try std.fs.cwd().readFileAlloc(
        alloc,
        "tests/fixtures/fingerprints/signal-package-v2.bin",
        1 << 16,
    );
    defer alloc.free(fixture);

    var frame_buf: [header_size + 1 << 16]u8 = undefined;
    const frame = try buildFrame(signal_package_type, fixture, &frame_buf);

    var stream = try std.net.tcpConnectToHost(alloc, "127.0.0.1", spawned.port);
    defer stream.close();
    try stream.writeAll(frame);

    var reply_buf: [header_size + 1 << 16]u8 = undefined;
    try expectHashReply(try readFrame(stream.reader(), &reply_buf));

    // SIGTERM (Child.kill on POSIX): the worker stops accepting, drains, and
    // exits 0. The idle read deadline (500ms) bounds the drain.
    _ = spawned.child.kill() catch {};
    const term = try spawned.child.wait();
    // Compare the union's active tag (0.14.1 rejects coercing the enum to
    // the union in expectEqual on Linux); then check the exit code.
    try std.testing.expectEqual(std.process.Child.Term.Exited, std.meta.activeTag(term));
    try std.testing.expectEqual(@as(u8, 0), term.Exited);
}
