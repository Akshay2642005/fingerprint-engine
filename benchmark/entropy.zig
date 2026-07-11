/// Entropy benchmarks: shannonEntropy, fingerprintEntropy.

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
    .{ .id = FeatureID.UserAgent, .value = FeatureValue{ .String = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" } },
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

pub fn benchShannonEntropy(bench_io: *timing.BenchIo) main.BenchmarkResult {
    const data = [_]u8{ 0x48, 0x65, 0x6c, 0x6c, 0x6f } ** 20; // 100 bytes of patterned data
    const iters: u64 = 1000;

    // Warmup
    var i: u64 = 0;
    while (i < main.warmup_iterations) : (i += 1) {
        _ = core.entropy.shannonEntropy(&data);
    }

    const start = bench_io.timestamp();
    i = 0;
    while (i < iters) : (i += 1) {
        _ = core.entropy.shannonEntropy(&data);
    }
    const total_ns = bench_io.elapsed(start);

    return .{
        .name = "entropy: shannonEntropy",
        .iterations = iters,
        .total_time_ns = total_ns,
        .ops_per_sec = @as(f64, @floatFromInt(iters)) / (@as(f64, @floatFromInt(total_ns)) / 1_000_000_000.0),
        .avg_ns = @as(f64, @floatFromInt(total_ns)) / @as(f64, @floatFromInt(iters)),
        .min_ns = 0,
        .max_ns = 0,
    };
}

pub fn benchFingerprintEntropy(bench_io: *timing.BenchIo) main.BenchmarkResult {
    const iters: u64 = 500;

    // Warmup
    var i: u64 = 0;
    while (i < main.warmup_iterations) : (i += 1) {
        _ = core.entropy.fingerprintEntropy(sample_fp);
    }

    const start = bench_io.timestamp();
    i = 0;
    while (i < iters) : (i += 1) {
        _ = core.entropy.fingerprintEntropy(sample_fp);
    }
    const total_ns = bench_io.elapsed(start);

    return .{
        .name = "entropy: fingerprintEntropy",
        .iterations = iters,
        .total_time_ns = total_ns,
        .ops_per_sec = @as(f64, @floatFromInt(iters)) / (@as(f64, @floatFromInt(total_ns)) / 1_000_000_000.0),
        .avg_ns = @as(f64, @floatFromInt(total_ns)) / @as(f64, @floatFromInt(iters)),
        .min_ns = 0,
        .max_ns = 0,
    };
}
