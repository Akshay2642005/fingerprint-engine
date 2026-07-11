/// Fingerprint Engine — Benchmark Harness
///
/// Usage: zig build bench
///
/// Each benchmark reports throughput (ops/sec) and latency over the
/// configured number of iterations. Results are printed to stdout in
/// a tabular format suitable for CI capture and regression tracking.
const std = @import("std");
const builtin = @import("builtin");
const timing = @import("timing.zig");

pub const BenchmarkResult = struct {
    name: []const u8,
    iterations: u64,
    total_time_ns: u64,
    ops_per_sec: f64,
    avg_ns: f64,
    min_ns: u64,
    max_ns: u64,
};

pub const BenchmarkFn = *const fn (bench_io: *timing.BenchIo) BenchmarkResult;

pub const BenchmarkDescriptor = struct {
    name: []const u8,
    func: BenchmarkFn,
};

const benchmarks: []const BenchmarkDescriptor = &.{
    .{ .name = "hashing: hashFeature", .func = @import("hashing.zig").benchHashFeature },
    .{ .name = "hashing: hashFingerprint", .func = @import("hashing.zig").benchHashFingerprint },
    .{ .name = "hashing: incremental hasher", .func = @import("hashing.zig").benchIncrementalHasher },
    .{ .name = "serialization: binary encode", .func = @import("serialization.zig").benchBinaryEncode },
    .{ .name = "serialization: json encode", .func = @import("serialization.zig").benchJsonEncode },
    .{ .name = "normalization: validateTypes", .func = @import("normalization.zig").benchValidateTypes },
    .{ .name = "normalization: checkBounds", .func = @import("normalization.zig").benchCheckBounds },
    .{ .name = "normalization: normalize", .func = @import("normalization.zig").benchNormalize },
    .{ .name = "similarity: featureScore", .func = @import("similarity.zig").benchFeatureScore },
    .{ .name = "similarity: fingerprintScore", .func = @import("similarity.zig").benchFingerprintScore },
    .{ .name = "entropy: shannonEntropy", .func = @import("entropy.zig").benchShannonEntropy },
    .{ .name = "entropy: fingerprintEntropy", .func = @import("entropy.zig").benchFingerprintEntropy },
};

pub const warmup_iterations: u64 = 100;

pub const Duration = struct {
    buf: [32]u8,
    len: usize,

    pub fn slice(self: *const Duration) []const u8 {
        return self.buf[0..self.len];
    }
};

/// Format a duration in nanoseconds to a human-readable string.
pub fn formatDuration(ns: u64) Duration {
    var buf: [32]u8 = undefined;
    const result = if (ns >= 1_000_000_000)
        std.fmt.bufPrint(&buf, "{d:.2}s", .{@as(f64, @floatFromInt(ns)) / 1_000_000_000.0}) catch unreachable
    else if (ns >= 1_000_000)
        std.fmt.bufPrint(&buf, "{d:.2}ms", .{@as(f64, @floatFromInt(ns)) / 1_000_000.0}) catch unreachable
    else if (ns >= 1_000)
        std.fmt.bufPrint(&buf, "{d:.2}µs", .{@as(f64, @floatFromInt(ns)) / 1_000.0}) catch unreachable
    else
        std.fmt.bufPrint(&buf, "{d}ns", .{ns}) catch unreachable;
    return .{ .buf = buf, .len = result.len };
}

pub fn main() !void {
    var bench_io = timing.BenchIo.init(std.heap.page_allocator);
    defer bench_io.deinit();

    std.debug.print("Fingerprint Engine — Benchmark Harness\n", .{});
    std.debug.print("Zig {d}.{d}.{d} | {s} | {s}\n", .{
        builtin.zig_version.major,
        builtin.zig_version.minor,
        builtin.zig_version.patch,
        @tagName(builtin.mode),
        @tagName(builtin.cpu.arch),
    });
    std.debug.print("{s:->60}\n", .{"-"});
    std.debug.print("  {s:40} {s:>10} {s:>10} {s:>10} {s:>10}\n", .{
        "Benchmark", "Ops/Sec", "Avg", "Min", "Max",
    });
    std.debug.print("{s:->60}\n", .{"-"});

    for (benchmarks) |b| {
        const result = b.func(&bench_io);
        const avg = formatDuration(@intFromFloat(result.avg_ns));
        const min = formatDuration(result.min_ns);
        const max = formatDuration(result.max_ns);
        std.debug.print("  {s:40} {d:>10.0} {s:>10} {s:>10} {s:>10}\n", .{
            result.name,
            result.ops_per_sec,
            avg.slice(),
            min.slice(),
            max.slice(),
        });
    }

    std.debug.print("{s:->60}\n", .{"-"});
    std.debug.print("  {d} benchmarks completed\n", .{benchmarks.len});
}
