const std = @import("std");
const features = @import("model");
const fingerprint = @import("model");
const validation = @import("../validation/root.zig");
const normalization = @import("../normalization/root.zig");
const entropy = @import("../entropy/root.zig");

const Fingerprint = fingerprint.Fingerprint;
const FeatureID = features.FeatureID;
const Registry = features.Registry;

// C-5: named thresholds for risk scoring.
const MISSING_PENALTY_PER: f64 = 0.15;
const MISSING_CAP: f64 = 0.4;
const NORM_PENALTY_PER: f64 = 0.05;
const NORM_CAP: f64 = 0.2;
const LOW_COVERAGE_THRESHOLD: f64 = 0.5;
const LOW_ENTROPY_THRESHOLD: f64 = 4.0;
const LOW_ENTROPY_PENALTY_PER: f64 = 0.05;

/// Flags indicating specific risk factors detected.
pub const RiskFlag = enum {
    missing_required_feature,
    bound_violation,
    type_mismatch,
    low_feature_coverage,
    low_fingerprint_entropy,
};

/// Result of a risk assessment.
pub const RiskAssessment = struct {
    /// Overall risk score (0.0 = no risk, 1.0 = very high risk).
    score: f64,
    /// Human-readable description of the risk level.
    label: []const u8,
    /// Risk flags triggered by this fingerprint (caller owns memory).
    flags: []RiskFlag,
    /// How many features were present.
    feature_count: usize,
    /// How many features are defined in the registry (total).
    total_defined: usize,
};

/// Computes a risk assessment for a fingerprint.
///
/// Factors analyzed:
/// 1. Missing required features → increases risk
/// 2. Bound/type violations → increases risk
/// 3. Feature coverage (low coverage → higher risk)
/// 4. Overall fingerprint entropy (low entropy → higher risk, suggests spoofing)
///
/// Caller owns `result.flags` (free with `allocator.free`).
pub fn computeRisk(fp: Fingerprint, allocator: std.mem.Allocator) !RiskAssessment {
    const total = Registry.count();
    const feature_count = fp.features.len;

    // ── Gather evidence ──
    const missing = try validation.checkRequired(fp, allocator);
    defer allocator.free(missing);

    const norm_warnings = try normalization.normalize(fp, allocator);
    defer allocator.free(norm_warnings);

    const coverage_ratio = if (total > 0)
        @as(f64, @floatFromInt(feature_count)) / @as(f64, @floatFromInt(total))
    else
        0.0;

    const fp_entropy = entropy.fingerprintEntropy(fp);

    // ── Build flags ──
    var flags: std.ArrayListUnmanaged(RiskFlag) = .empty;
    defer flags.deinit(allocator);

    if (missing.len > 0)
        try flags.append(allocator, .missing_required_feature);

    // Check for bound/type violations
    for (norm_warnings) |w| {
        switch (w) {
            .bound_violation => {
                var found = false;
                for (flags.items) |f| {
                    if (f == .bound_violation) {
                        found = true;
                        break;
                    }
                }
                if (!found) try flags.append(allocator, .bound_violation);
            },
            .type_mismatch => {
                var found = false;
                for (flags.items) |f| {
                    if (f == .type_mismatch) {
                        found = true;
                        break;
                    }
                }
                if (!found) try flags.append(allocator, .type_mismatch);
            },
        }
    }

    if (coverage_ratio < 0.3)
        try flags.append(allocator, .low_feature_coverage);

    if (fp_entropy < 1.0)
        try flags.append(allocator, .low_fingerprint_entropy);

    // ── Compute weighted score ──
    var score: f64 = 0.0;

    // Missing required: severe penalty (up to 0.4)
    score += @min(@as(f64, @floatFromInt(missing.len)) * MISSING_PENALTY_PER, MISSING_CAP);

    // Normalization violations: moderate penalty (up to 0.2)
    score += @min(@as(f64, @floatFromInt(norm_warnings.len)) * NORM_PENALTY_PER, NORM_CAP);

    // Low coverage: penalize inverse of coverage (up to 0.2)
    if (coverage_ratio < LOW_COVERAGE_THRESHOLD) {
        score += (LOW_COVERAGE_THRESHOLD - coverage_ratio) * 0.4;
    }

    // Low entropy: penalize entropy deficit (up to 0.2)
    if (fp_entropy < LOW_ENTROPY_THRESHOLD) {
        score += (LOW_ENTROPY_THRESHOLD - fp_entropy) * LOW_ENTROPY_PENALTY_PER;
    }

    score = @min(score, 1.0);
    std.debug.assert(score >= 0.0 and score <= 1.0);

    const label = if (score > 0.7) "high" else if (score > 0.3) "medium" else "low";

    const result = RiskAssessment{
        .score = score,
        .label = label,
        .flags = try flags.toOwnedSlice(allocator),
        .feature_count = feature_count,
        .total_defined = total,
    };
    std.debug.assert(result.flags.len > 0 or score <= 0.5);
    return result;
}
