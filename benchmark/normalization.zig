/// Normalization benchmarks: validateTypes, checkBounds, normalize.
const std = @import("std");
const core = @import("core");
const main = @import("main.zig");
const timing = @import("timing.zig");

const FeatureID = core.features.FeatureID;
const FeatureValue = core.fingerprint.FeatureValue;
const Feature = core.fingerprint.Feature;

const sample_feats: [10]Feature = .{
    .{ .id = FeatureID.CookieEnabled, .value = FeatureValue{ .Boolean = true } },
    .{ .id = FeatureID.UserAgent, .value = FeatureValue{ .String = "Mozilla/5.0" } },
    .{ .id = FeatureID.Language, .value = FeatureValue{ .String = "en-US" } },
    .{ .id = FeatureID.Platform, .value = FeatureValue{ .String = "Win32" } },
    .{ .id = FeatureID.HardwareConcurrency, .value = FeatureValue{ .Integer = 8 } },
    .{ .id = FeatureID.DeviceMemory, .value = FeatureValue{ .Integer = 8 } },
    .{ .id = FeatureID.ScreenWidth, .value = FeatureValue{ .Integer = 1920 } },
    .{ .id = FeatureID.ScreenHeight, .value = FeatureValue{ .Integer = 1080 } },
    .{ .id = FeatureID.Timezone, .value = FeatureValue{ .String = "America/New_York" } },
    .{ .id = FeatureID.CanvasHash, .value = FeatureValue{ .Bytes = &[_]u8{ 0xde, 0xad } } },
};

const sample_fp = core.fingerprint.Fingerprint{
    .metadata = .{
        .schema_version = 1,
        .sdk_version = "0.1.0",
        .collected_at = 0,
    },
    .features = &sample_feats,
};

pub fn benchValidateTypes(bench_io: *timing.BenchIo) main.BenchmarkResult {
    const iters: u64 = 500;

    // Warmup
    var i: u64 = 0;
    while (i < main.warmup_iterations) : (i += 1) {
        const result = core.normalization.validateTypes(sample_fp, std.heap.page_allocator) catch @panic("validate");
        std.heap.page_allocator.free(result);
    }

    var min_ns: u64 = std.math.maxInt(u64);
    var max_ns: u64 = 0;
    var total_ns: u64 = 0;

    i = 0;
    while (i < iters) : (i += 1) {
        const iter_start = bench_io.timestamp();
        const result = core.normalization.validateTypes(sample_fp, std.heap.page_allocator) catch @panic("validate");
        std.heap.page_allocator.free(result);
        const iter_ns = bench_io.elapsed(iter_start);
        total_ns += iter_ns;
        if (iter_ns < min_ns) min_ns = iter_ns;
        if (iter_ns > max_ns) max_ns = iter_ns;
    }

    return .{
        .name = "normalization: validateTypes",
        .iterations = iters,
        .total_time_ns = total_ns,
        .ops_per_sec = @as(f64, @floatFromInt(iters)) / (@as(f64, @floatFromInt(total_ns)) / 1_000_000_000.0),
        .avg_ns = @as(f64, @floatFromInt(total_ns)) / @as(f64, @floatFromInt(iters)),
        .min_ns = min_ns,
        .max_ns = max_ns,
    };
}

pub fn benchCheckBounds(bench_io: *timing.BenchIo) main.BenchmarkResult {
    const iters: u64 = 500;

    // Warmup
    var i: u64 = 0;
    while (i < main.warmup_iterations) : (i += 1) {
        const result = core.normalization.checkAllBounds(sample_fp, std.heap.page_allocator) catch @panic("bounds");
        std.heap.page_allocator.free(result);
    }

    var min_ns: u64 = std.math.maxInt(u64);
    var max_ns: u64 = 0;
    var total_ns: u64 = 0;

    i = 0;
    while (i < iters) : (i += 1) {
        const iter_start = bench_io.timestamp();
        const result = core.normalization.checkAllBounds(sample_fp, std.heap.page_allocator) catch @panic("bounds");
        std.heap.page_allocator.free(result);
        const iter_ns = bench_io.elapsed(iter_start);
        total_ns += iter_ns;
        if (iter_ns < min_ns) min_ns = iter_ns;
        if (iter_ns > max_ns) max_ns = iter_ns;
    }

    return .{
        .name = "normalization: checkBounds",
        .iterations = iters,
        .total_time_ns = total_ns,
        .ops_per_sec = @as(f64, @floatFromInt(iters)) / (@as(f64, @floatFromInt(total_ns)) / 1_000_000_000.0),
        .avg_ns = @as(f64, @floatFromInt(total_ns)) / @as(f64, @floatFromInt(iters)),
        .min_ns = min_ns,
        .max_ns = max_ns,
    };
}

pub fn benchNormalize(bench_io: *timing.BenchIo) main.BenchmarkResult {
    const iters: u64 = 200;

    // Warmup
    var i: u64 = 0;
    while (i < 20) : (i += 1) {
        const result = core.normalization.normalize(sample_fp, std.heap.page_allocator) catch @panic("normalize");
        std.heap.page_allocator.free(result);
    }

    var min_ns: u64 = std.math.maxInt(u64);
    var max_ns: u64 = 0;
    var total_ns: u64 = 0;

    i = 0;
    while (i < iters) : (i += 1) {
        const iter_start = bench_io.timestamp();
        const result = core.normalization.normalize(sample_fp, std.heap.page_allocator) catch @panic("normalize");
        std.heap.page_allocator.free(result);
        const iter_ns = bench_io.elapsed(iter_start);
        total_ns += iter_ns;
        if (iter_ns < min_ns) min_ns = iter_ns;
        if (iter_ns > max_ns) max_ns = iter_ns;
    }

    return .{
        .name = "normalization: normalize",
        .iterations = iters,
        .total_time_ns = total_ns,
        .ops_per_sec = @as(f64, @floatFromInt(iters)) / (@as(f64, @floatFromInt(total_ns)) / 1_000_000_000.0),
        .avg_ns = @as(f64, @floatFromInt(total_ns)) / @as(f64, @floatFromInt(iters)),
        .min_ns = min_ns,
        .max_ns = max_ns,
    };
}
