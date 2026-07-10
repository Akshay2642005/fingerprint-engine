const std = @import("std");
const fingerprint = @import("../fingerprint/root.zig");

const FeatureValue = fingerprint.FeatureValue;

const INT_MAX_RANGE: f64 = 1000000.0;
const FLOAT_MAX_RANGE: f64 = 10000.0;

/// Computes the similarity score between two FeatureValues (0.0 — completely different, 1.0 — identical).
pub fn featureScore(a: FeatureValue, b: FeatureValue) f64 {
    switch (a) {
        .Boolean => return if (a.Boolean == b.Boolean) 1.0 else 0.0,
        .Integer => return integerScore(a.Integer, b.Integer),
        .Float => return floatScore(a.Float, b.Float),
        .String => return stringScore(a.String, b.String),
        .Bytes => return bytesScore(a.Bytes, b.Bytes),
        .StringArray => return stringArrayScore(a.StringArray, b.StringArray),
        .IntegerArray => return integerArrayScore(a.IntegerArray, b.IntegerArray),
        .FloatArray => return floatArrayScore(a.FloatArray, b.FloatArray),
        .BytesArray => return bytesArrayScore(a.BytesArray, b.BytesArray),
    }
}

fn integerScore(a: i64, b: i64) f64 {
    if (a == b) return 1.0;
    const diff = @abs(a - b);
    return 1.0 - @min(@as(f64, @floatFromInt(diff)) / INT_MAX_RANGE, 1.0);
}

fn floatScore(a: f64, b: f64) f64 {
    if (a == b) return 1.0;
    if (!std.math.isFinite(a) or !std.math.isFinite(b)) return 0.0;
    const diff = @abs(a - b);
    return 1.0 - @min(diff / FLOAT_MAX_RANGE, 1.0);
}

/// Simple character-level ratio: 1 — normalized edit distance
fn stringScore(a: []const u8, b: []const u8) f64 {
    if (a.len == 0 and b.len == 0) return 1.0;
    if (a.len == 0 or b.len == 0) return 0.0;
    if (std.mem.eql(u8, a, b)) return 1.0;

    const dist = levenshteinDistance(a, b);
    const max_len = @max(a.len, b.len);
    return 1.0 - (@as(f64, @floatFromInt(dist)) / @as(f64, @floatFromInt(max_len)));
}

fn bytesScore(a: []const u8, b: []const u8) f64 {
    if (std.mem.eql(u8, a, b)) return 1.0;
    return 0.0;
}

fn stringArrayScore(a: []const []const u8, b: []const []const u8) f64 {
    return jaccardStrings(a, b);
}

fn integerArrayScore(a: []const i64, b: []const i64) f64 {
    return jaccardIntegers(a, b);
}

fn floatArrayScore(a: []const f64, b: []const f64) f64 {
    return jaccardFloats(a, b);
}

fn bytesArrayScore(a: []const []const u8, b: []const []const u8) f64 {
    return jaccardByteSlices(a, b);
}

// ── Jaccard similarity ──

fn jaccardStrings(a: []const []const u8, b: []const []const u8) f64 {
    if (a.len == 0 and b.len == 0) return 1.0;
    var intersection: usize = 0;
    for (a) |item_a| {
        for (b) |item_b| {
            if (std.mem.eql(u8, item_a, item_b)) {
                intersection += 1;
                break;
            }
        }
    }
    const union_size = a.len + b.len - intersection;
    if (union_size == 0) return 1.0;
    return @as(f64, @floatFromInt(intersection)) / @as(f64, @floatFromInt(union_size));
}

fn jaccardIntegers(a: []const i64, b: []const i64) f64 {
    if (a.len == 0 and b.len == 0) return 1.0;
    var intersection: usize = 0;
    for (a) |item_a| {
        for (b) |item_b| {
            if (item_a == item_b) {
                intersection += 1;
                break;
            }
        }
    }
    const union_size = a.len + b.len - intersection;
    if (union_size == 0) return 1.0;
    return @as(f64, @floatFromInt(intersection)) / @as(f64, @floatFromInt(union_size));
}

fn jaccardFloats(a: []const f64, b: []const f64) f64 {
    if (a.len == 0 and b.len == 0) return 1.0;
    var intersection: usize = 0;
    for (a) |item_a| {
        for (b) |item_b| {
            if (item_a == item_b) {
                intersection += 1;
                break;
            }
        }
    }
    const union_size = a.len + b.len - intersection;
    if (union_size == 0) return 1.0;
    return @as(f64, @floatFromInt(intersection)) / @as(f64, @floatFromInt(union_size));
}

fn jaccardByteSlices(a: []const []const u8, b: []const []const u8) f64 {
    if (a.len == 0 and b.len == 0) return 1.0;
    var intersection: usize = 0;
    for (a) |item_a| {
        for (b) |item_b| {
            if (std.mem.eql(u8, item_a, item_b)) {
                intersection += 1;
                break;
            }
        }
    }
    const union_size = a.len + b.len - intersection;
    if (union_size == 0) return 1.0;
    return @as(f64, @floatFromInt(intersection)) / @as(f64, @floatFromInt(union_size));
}

// ── Levenshtein distance ──

fn levenshteinDistance(a: []const u8, b: []const u8) usize {
    const m = a.len;
    const n = b.len;
    if (m == 0) return n;
    if (n == 0) return m;

    // Use two-row technique for O(min(m,n)) memory
    var prev: [256]usize = undefined;
    var curr: [256]usize = undefined;
    const max_dim = @min(m, n) + 1;
    if (max_dim > 256) {
        // Fallback for very long strings: length ratio only
        const larger = @max(m, n);
        const smaller = @min(m, n);
        return larger - smaller;
    }

    // Ensure m is the shorter dimension for the row
    const short: []const u8 = if (m <= n) a else b;
    const long: []const u8 = if (m <= n) b else a;
    const short_len = short.len;
    const long_len = long.len;

    for (0..short_len + 1) |i| {
        prev[i] = i;
    }

    for (1..long_len + 1) |j| {
        curr[0] = j;
        for (1..short_len + 1) |i| {
            const cost: usize = if (short[i - 1] == long[j - 1]) 0 else 1;
            curr[i] = @min(
                @min(curr[i - 1] + 1, prev[i] + 1),
                prev[i - 1] + cost,
            );
        }
        @memcpy(prev[0..short_len + 1], curr[0..short_len + 1]);
    }

    return prev[short_len];
}
