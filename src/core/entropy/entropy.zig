const std = @import("std");
const features = @import("../features/root.zig");
const fingerprint = @import("../fingerprint/root.zig");

const FeatureValue = fingerprint.FeatureValue;
const Fingerprint = fingerprint.Fingerprint;
const Registry = features.Registry;

/// Computes the Shannon entropy of a byte slice (bits per byte, 0.0–8.0).
/// 0.0 = all bytes are the same, 8.0 = perfectly random distribution.
pub fn shannonEntropy(data: []const u8) f64 {
    if (data.len == 0) return 0.0;

    var freq: [256]usize = [_]usize{0} ** 256;
    for (data) |byte| {
        freq[byte] += 1;
    }

    const len_f = @as(f64, @floatFromInt(data.len));
    var entropy: f64 = 0.0;
    for (freq) |count| {
        if (count > 0) {
            const p = @as(f64, @floatFromInt(count)) / len_f;
            entropy -= p * @log2(p);
        }
    }

    return entropy;
}

/// Converts a FeatureValue to a byte slice for entropy computation.
fn valueToBytes(value: FeatureValue, buf: *[1024]u8) []const u8 {
    switch (value) {
        .Boolean => |v| {
            buf[0] = if (v) 1 else 0;
            return buf[0..1];
        },
        .Integer => |v| {
            std.mem.writeInt(i64, buf[0..8], v, .little);
            return buf[0..8];
        },
        .Float => |v| {
            std.mem.writeInt(u64, buf[0..8], @bitCast(v), .little);
            return buf[0..8];
        },
        .String => |v| return v,
        .Bytes => |v| return v,
        .StringArray => |v| {
            var pos: usize = 0;
            for (v) |item| {
                if (pos + item.len > 1024) break;
                @memcpy(buf[pos..][0..item.len], item);
                pos += item.len;
                if (pos < 1024) { buf[pos] = 0; pos += 1; }
            }
            return buf[0..pos];
        },
        .IntegerArray => |v| {
            var pos: usize = 0;
            for (v) |item| {
                if (pos + 8 > 1024) break;
                std.mem.writeInt(i64, buf[pos..][0..8], item, .little);
                pos += 8;
            }
            return buf[0..pos];
        },
        .FloatArray => |v| {
            var pos: usize = 0;
            for (v) |item| {
                if (pos + 8 > 1024) break;
                std.mem.writeInt(u64, buf[pos..][0..8], @bitCast(item), .little);
                pos += 8;
            }
            return buf[0..pos];
        },
        .BytesArray => |v| {
            var pos: usize = 0;
            for (v) |item| {
                if (pos + item.len > 1024) break;
                @memcpy(buf[pos..][0..item.len], item);
                pos += item.len;
                if (pos < 1024) { buf[pos] = 0; pos += 1; }
            }
            return buf[0..pos];
        },
    }
}

/// Computes the Shannon entropy of a FeatureValue (bits per byte, 0.0–8.0).
pub fn featureEntropy(value: FeatureValue) f64 {
    var buf: [1024]u8 = undefined;
    const bytes = valueToBytes(value, &buf);
    return shannonEntropy(bytes);
}

/// Computes the weighted entropy of a full Fingerprint (bits per byte, 0.0–8.0).
/// Uses feature weights from FeatureDefinition for weighted average.
pub fn fingerprintEntropy(fp: Fingerprint) f64 {
    if (fp.features.len == 0) return 0.0;

    var weighted_sum: f64 = 0.0;
    var total_weight: f64 = 0.0;

    for (fp.features) |feat| {
        const weight = @as(f64, @floatFromInt(Registry.get(feat.id).weight));
        const h = featureEntropy(feat.value);
        weighted_sum += h * weight;
        total_weight += weight;
    }

    if (total_weight == 0.0) return 0.0;
    return weighted_sum / total_weight;
}
