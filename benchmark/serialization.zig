/// Serialization benchmarks: binary encode, JSON encode.
const std = @import("std");
const core = @import("core");
const main = @import("main.zig");
const timing = @import("timing.zig");

const FeatureID = core.features.FeatureID;
const FeatureValue = core.fingerprint.FeatureValue;
const Feature = core.fingerprint.Feature;
const Fingerprint = core.fingerprint.Fingerprint;

const sample_feats: [5]Feature = .{
    .{ .id = FeatureID.CookieEnabled, .value = FeatureValue{ .Boolean = true } },
    .{ .id = FeatureID.UserAgent, .value = FeatureValue{ .String = "Mozilla/5.0" } },
    .{ .id = FeatureID.HardwareConcurrency, .value = FeatureValue{ .Integer = 8 } },
    .{ .id = FeatureID.ScreenWidth, .value = FeatureValue{ .Integer = 1920 } },
    .{ .id = FeatureID.Timezone, .value = FeatureValue{ .String = "America/New_York" } },
};

const sample_fp: Fingerprint = .{
    .metadata = .{
        .schema_version = 1,
        .sdk_version = "0.1.0",
        .collected_at = 0,
    },
    .features = &sample_feats,
};

pub fn benchBinaryEncode(bench_io: *timing.BenchIo) main.BenchmarkResult {
    const iters: u64 = 1000;

    // Warmup
    var i: u64 = 0;
    while (i < main.warmup_iterations) : (i += 1) {
        var al: std.ArrayList(u8) = .empty;
        al.ensureTotalCapacity(std.heap.page_allocator, 1024) catch @panic("oom");
        var w = std.Io.Writer.fromArrayList(&al);
        core.serialization.encode(&w, sample_fp) catch @panic("encode");
    }

    var min_ns: u64 = std.math.maxInt(u64);
    var max_ns: u64 = 0;
    var total_ns: u64 = 0;

    i = 0;
    while (i < iters) : (i += 1) {
        const iter_start = bench_io.timestamp();
        var al: std.ArrayList(u8) = .empty;
        al.ensureTotalCapacity(std.heap.page_allocator, 1024) catch @panic("oom");
        var w = std.Io.Writer.fromArrayList(&al);
        core.serialization.encode(&w, sample_fp) catch @panic("encode");
        const iter_ns = bench_io.elapsed(iter_start);
        total_ns += iter_ns;
        if (iter_ns < min_ns) min_ns = iter_ns;
        if (iter_ns > max_ns) max_ns = iter_ns;
    }

    return .{
        .name = "serialization: binary encode",
        .iterations = iters,
        .total_time_ns = total_ns,
        .ops_per_sec = @as(f64, @floatFromInt(iters)) / (@as(f64, @floatFromInt(total_ns)) / 1_000_000_000.0),
        .avg_ns = @as(f64, @floatFromInt(total_ns)) / @as(f64, @floatFromInt(iters)),
        .min_ns = min_ns,
        .max_ns = max_ns,
    };
}

pub fn benchJsonEncode(bench_io: *timing.BenchIo) main.BenchmarkResult {
    const iters: u64 = 500;

    // Warmup
    var i: u64 = 0;
    while (i < 20) : (i += 1) {
        var al: std.ArrayList(u8) = .empty;
        al.ensureTotalCapacity(std.heap.page_allocator, 4096) catch @panic("oom");
        var w = std.Io.Writer.fromArrayList(&al);
        core.serialization.jsonEncode(&w, sample_fp) catch @panic("json");
    }

    var min_ns: u64 = std.math.maxInt(u64);
    var max_ns: u64 = 0;
    var total_ns: u64 = 0;

    i = 0;
    while (i < iters) : (i += 1) {
        const iter_start = bench_io.timestamp();
        var al: std.ArrayList(u8) = .empty;
        al.ensureTotalCapacity(std.heap.page_allocator, 4096) catch @panic("oom");
        var w = std.Io.Writer.fromArrayList(&al);
        core.serialization.jsonEncode(&w, sample_fp) catch @panic("json");
        const iter_ns = bench_io.elapsed(iter_start);
        total_ns += iter_ns;
        if (iter_ns < min_ns) min_ns = iter_ns;
        if (iter_ns > max_ns) max_ns = iter_ns;
    }

    return .{
        .name = "serialization: json encode",
        .iterations = iters,
        .total_time_ns = total_ns,
        .ops_per_sec = @as(f64, @floatFromInt(iters)) / (@as(f64, @floatFromInt(total_ns)) / 1_000_000_000.0),
        .avg_ns = @as(f64, @floatFromInt(total_ns)) / @as(f64, @floatFromInt(iters)),
        .min_ns = min_ns,
        .max_ns = max_ns,
    };
}
