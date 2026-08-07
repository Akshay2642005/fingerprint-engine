//! Integration and end-to-end tests for Fingerprint Engine.
//!
//! The test binary itself contains no engine code: everything is driven
//! through pre-built executables (`fingerprint-bench`, `scripts`) spawned as
//! subprocesses, with stdout/stderr and exit status asserted.
//!
//! Executable paths are injected at build time by build.zig (test_options),
//! so `zig build test-integration` always exercises the binaries it built.
//! The worker end-to-end pipe test (spawn worker, feed a SignalPackage over
//! stdin, assert the canonical fingerprint on stdout) lands with the worker
//! in commit 12.
const std = @import("std");

const Shell = @import("testing/shell.zig");

const bench_exe: []const u8 = @import("test_options").bench_exe;
const scripts_exe: []const u8 = @import("test_options").scripts_exe;

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
