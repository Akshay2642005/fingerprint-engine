const std = @import("std");
const fingerprint = @import("core").fingerprint;
const features = @import("core").features;
const serialization = @import("core").serialization;

pub fn main() !void {
    const meta = fingerprint.FingerprintMetadata{ .schema_version = 1, .sdk_version = "0.1.0", .collected_at = 1700000000 };
    const fp = fingerprint.Fingerprint{
        .metadata = meta,
        .features = &.{
            fingerprint.Feature{ .id = features.FeatureID.CookieEnabled, .value = fingerprint.FeatureValue{ .Boolean = true } },
            fingerprint.Feature{ .id = features.FeatureID.HardwareConcurrency, .value = fingerprint.FeatureValue{ .Integer = 8 } },
            fingerprint.Feature{ .id = features.FeatureID.UserAgent, .value = fingerprint.FeatureValue{ .String = "Mozilla/5.0" } },
        },
    };

    var buf: [1024]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try serialization.jsonEncode(&w, fp);
    std.debug.print("{s}\n", .{buf[0..w.end]});
}
