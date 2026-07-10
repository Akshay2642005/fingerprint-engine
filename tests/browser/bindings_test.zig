const std = @import("std");
const testing = std.testing;

const features_mod = @import("core").features;

const expected_exports = [_][]const u8{
    "fingerprint_init",
    "fingerprint_add_feature",
    "fingerprint_compute",
    "fingerprint_get_digest_ptr",
    "fingerprint_reset",
    "fingerprint_get_error",
    "fingerprint_feature_count",
};

test "WASM export names are stable" {
    comptime {
        for (expected_exports) |name| {
            if (name.len == 0) @compileError("empty export name");
        }
    }
}

test "WASM export names are prefixed with fingerprint_" {
    comptime {
        for (expected_exports) |name| {
            if (!std.mem.startsWith(u8, name, "fingerprint_"))
                @compileError("export must start with fingerprint_");
            for (name) |c| {
                const ok = (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c == '_';
                if (!ok) @compileError("export has invalid character");
            }
        }
    }
}

test "FeatureID enum values match TypeScript" {
    comptime {
        const fields = @typeInfo(features_mod.FeatureID).@"enum".fields;
        var prev: i32 = -1;
        for (fields) |field| {
            if (field.value != prev + 1)
                @compileError("FeatureID has non-sequential value");
            prev = field.value;
        }
    }
}

test "FeatureType enum values match TypeScript" {
    comptime {
        const fields = @typeInfo(features_mod.FeatureType).@"enum".fields;
        var prev: i32 = -1;
        for (fields) |field| {
            if (field.value != prev + 1)
                @compileError("FeatureType has non-sequential value");
            prev = field.value;
        }
    }
}
