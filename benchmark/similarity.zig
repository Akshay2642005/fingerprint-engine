/// Similarity benchmarks: featureScore, fingerprintScore.

const std = @import("std");
const core = @import("core");
const main = @import("main.zig");
const timing = @import("timing.zig");

const FeatureID = core.features.FeatureID;
const FeatureValue = core.fingerprint.FeatureValue;
const Feature = core.fingerprint.Feature;
const Fingerprint = core.fingerprint.Fingerprint;

const meta = core.fingerprint.FingerprintMetadata{
    .schema_version = 1,
    .sdk_version = "0.1.0",
    .collected_at = 0,
};

const feats_a: [4]Feature = .{
    .{ .id = FeatureID.CookieEnabled, .value = FeatureValue{ .Boolean = true } },
    .{ .id = FeatureID.UserAgent, .value = FeatureValue{ .String = "Mozilla/5.0 (Windows NT 10.0) Chrome/120" } },
    .{ .id = FeatureID.HardwareConcurrency, .value = FeatureValue{ .Integer = 8 } },
    .{ .id = FeatureID.ScreenWidth, .value = FeatureValue{ .Integer = 1920 } },
};

const feats_b: [4]Feature = .{
    .{ .id = FeatureID.CookieEnabled, .value = FeatureValue{ .Boolean = true } },
    .{ .id = FeatureID.UserAgent, .value = FeatureValue{ .String = "Mozilla/5.0 (Macintosh) Firefox/121" } },
    .{ .id = FeatureID.HardwareConcurrency, .value = FeatureValue{ .Integer = 10 } },
    .{ .id = FeatureID.ScreenWidth, .value = FeatureValue{ .Integer = 2560 } },
};

const fp_a: Fingerprint = .{ .metadata = meta, .features = &feats_a };
const fp_b: Fingerprint = .{ .metadata = meta, .features = &feats_b };

pub fn benchFeatureScore(bench_io: *timing.BenchIo) main.BenchmarkResult {
    const iters: u64 = 1000;

    // Warmup
    var i: u64 = 0;
    while (i < main.warmup_iterations) : (i += 1) {
        for (&feats_a, &feats_b) |fa, fb| {
            _ = core.similarity.featureScore(fa.value, fb.value);
        }
    }

    const start = bench_io.timestamp();
    i = 0;
    while (i < iters) : (i += 1) {
        for (&feats_a, &feats_b) |fa, fb| {
            _ = core.similarity.featureScore(fa.value, fb.value);
        }
    }
    const total_ns = bench_io.elapsed(start);

    return .{
        .name = "similarity: featureScore",
        .iterations = iters,
        .total_time_ns = total_ns,
        .ops_per_sec = @as(f64, @floatFromInt(iters * feats_a.len)) / (@as(f64, @floatFromInt(total_ns)) / 1_000_000_000.0),
        .avg_ns = @as(f64, @floatFromInt(total_ns)) / @as(f64, @floatFromInt(iters * feats_a.len)),
        .min_ns = 0,
        .max_ns = 0,
    };
}

pub fn benchFingerprintScore(bench_io: *timing.BenchIo) main.BenchmarkResult {
    const iters: u64 = 500;

    // Warmup
    var i: u64 = 0;
    while (i < main.warmup_iterations) : (i += 1) {
        _ = core.similarity.fingerprintScore(fp_a, fp_b);
    }

    const start = bench_io.timestamp();
    i = 0;
    while (i < iters) : (i += 1) {
        _ = core.similarity.fingerprintScore(fp_a, fp_b);
    }
    const total_ns = bench_io.elapsed(start);

    return .{
        .name = "similarity: fingerprintScore",
        .iterations = iters,
        .total_time_ns = total_ns,
        .ops_per_sec = @as(f64, @floatFromInt(iters)) / (@as(f64, @floatFromInt(total_ns)) / 1_000_000_000.0),
        .avg_ns = @as(f64, @floatFromInt(total_ns)) / @as(f64, @floatFromInt(iters)),
        .min_ns = 0,
        .max_ns = 0,
    };
}
