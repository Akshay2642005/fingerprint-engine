/// Hashing benchmarks: hashFeature, hashFingerprint, incremental hasher.
const std = @import("std");
const core = @import("core");
const main = @import("main.zig");
const timing = @import("timing.zig");

const FeatureID = core.features.FeatureID;
const FeatureValue = core.fingerprint.FeatureValue;
const Feature = core.fingerprint.Feature;

const sample_features: [10]Feature = .{
    .{ .id = FeatureID.CookieEnabled, .value = FeatureValue{ .Boolean = true } },
    .{ .id = FeatureID.UserAgent, .value = FeatureValue{ .String = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" } },
    .{ .id = FeatureID.Language, .value = FeatureValue{ .String = "en-US" } },
    .{ .id = FeatureID.Platform, .value = FeatureValue{ .String = "Win32" } },
    .{ .id = FeatureID.HardwareConcurrency, .value = FeatureValue{ .Integer = 8 } },
    .{ .id = FeatureID.DeviceMemory, .value = FeatureValue{ .Integer = 8 } },
    .{ .id = FeatureID.ScreenWidth, .value = FeatureValue{ .Integer = 1920 } },
    .{ .id = FeatureID.ScreenHeight, .value = FeatureValue{ .Integer = 1080 } },
    .{ .id = FeatureID.Timezone, .value = FeatureValue{ .String = "America/New_York" } },
    .{ .id = FeatureID.CanvasHash, .value = FeatureValue{ .Bytes = &[_]u8{ 0xde, 0xad, 0xbe, 0xef } } },
};

pub fn benchHashFeature(bench_io: *timing.BenchIo) main.BenchmarkResult {
    const iters: u64 = 1000;
    var out: [32]u8 = undefined;

    // Warmup
    var i: u64 = 0;
    while (i < main.warmup_iterations) : (i += 1) {
        for (sample_features) |f| {
            core.hashing.hashFeature(f.value, &out) catch @panic("hash");
        }
    }

    var min_ns: u64 = std.math.maxInt(u64);
    var max_ns: u64 = 0;
    var total_ns: u64 = 0;

    i = 0;
    while (i < iters) : (i += 1) {
        const iter_start = bench_io.timestamp();
        for (sample_features) |f| {
            core.hashing.hashFeature(f.value, &out) catch @panic("hash");
        }
        const iter_ns = bench_io.elapsed(iter_start);
        total_ns += iter_ns;
        if (iter_ns < min_ns) min_ns = iter_ns;
        if (iter_ns > max_ns) max_ns = iter_ns;
    }

    return .{
        .name = "hashing: hashFeature",
        .iterations = iters,
        .total_time_ns = total_ns,
        .ops_per_sec = @as(f64, @floatFromInt(iters * sample_features.len)) / (@as(f64, @floatFromInt(total_ns)) / 1_000_000_000.0),
        .avg_ns = @as(f64, @floatFromInt(total_ns)) / @as(f64, @floatFromInt(iters * sample_features.len)),
        .min_ns = min_ns,
        .max_ns = max_ns,
    };
}

pub fn benchHashFingerprint(bench_io: *timing.BenchIo) main.BenchmarkResult {
    const fp = core.fingerprint.Fingerprint{
        .metadata = .{
            .schema_version = 1,
            .sdk_version = "0.1.0",
            .collected_at = 0,
        },
        .features = &sample_features,
    };
    const iters: u64 = 1000;
    var out: [32]u8 = undefined;

    // Warmup
    var i: u64 = 0;
    while (i < main.warmup_iterations) : (i += 1) {
        core.hashing.hashFingerprint(fp, &out) catch @panic("hash");
    }

    var min_ns: u64 = std.math.maxInt(u64);
    var max_ns: u64 = 0;
    var total_ns: u64 = 0;

    i = 0;
    while (i < iters) : (i += 1) {
        const iter_start = bench_io.timestamp();
        core.hashing.hashFingerprint(fp, &out) catch @panic("hash");
        const iter_ns = bench_io.elapsed(iter_start);
        total_ns += iter_ns;
        if (iter_ns < min_ns) min_ns = iter_ns;
        if (iter_ns > max_ns) max_ns = iter_ns;
    }

    return .{
        .name = "hashing: hashFingerprint",
        .iterations = iters,
        .total_time_ns = total_ns,
        .ops_per_sec = @as(f64, @floatFromInt(iters)) / (@as(f64, @floatFromInt(total_ns)) / 1_000_000_000.0),
        .avg_ns = @as(f64, @floatFromInt(total_ns)) / @as(f64, @floatFromInt(iters)),
        .min_ns = min_ns,
        .max_ns = max_ns,
    };
}

pub fn benchIncrementalHasher(bench_io: *timing.BenchIo) main.BenchmarkResult {
    const iters: u64 = 1000;
    var out: [32]u8 = undefined;

    // Warmup
    var i: u64 = 0;
    while (i < main.warmup_iterations) : (i += 1) {
        var hasher = core.hashing.Hasher.init(1, "0.1.0", 0);
        for (sample_features) |f| {
            hasher.add(f.id, f.value) catch @panic("add");
        }
        hasher.final(&out);
    }

    var min_ns: u64 = std.math.maxInt(u64);
    var max_ns: u64 = 0;
    var total_ns: u64 = 0;

    i = 0;
    while (i < iters) : (i += 1) {
        const iter_start = bench_io.timestamp();
        var hasher = core.hashing.Hasher.init(1, "0.1.0", 0);
        for (sample_features) |f| {
            hasher.add(f.id, f.value) catch @panic("add");
        }
        hasher.final(&out);
        const iter_ns = bench_io.elapsed(iter_start);
        total_ns += iter_ns;
        if (iter_ns < min_ns) min_ns = iter_ns;
        if (iter_ns > max_ns) max_ns = iter_ns;
    }

    return .{
        .name = "hashing: incremental hasher",
        .iterations = iters,
        .total_time_ns = total_ns,
        .ops_per_sec = @as(f64, @floatFromInt(iters)) / (@as(f64, @floatFromInt(total_ns)) / 1_000_000_000.0),
        .avg_ns = @as(f64, @floatFromInt(total_ns)) / @as(f64, @floatFromInt(iters)),
        .min_ns = min_ns,
        .max_ns = max_ns,
    };
}
