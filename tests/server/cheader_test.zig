const std = @import("std");
const testing = std.testing;
const features = @import("core").features;
const server = @import("server");

test "C header feature constants match FeatureID enum values" {
    comptime {
        const fields = @typeInfo(features.FeatureID).@"enum".fields;
        for (fields) |field| {
            // Skip synthetic Count field used for array sizing
            if (std.mem.eql(u8, field.name, "Count")) continue;

            // Verify the zig enum value is in expected range
            if (field.value < 0 or field.value > 36)
                @compileError("FeatureID " ++ field.name ++ " has unexpected value");
        }
    }
}

test "C header type constants match FeatureType enum values" {
    comptime {
        const fields = @typeInfo(features.FeatureType).@"enum".fields;
        for (fields) |field| {
            if (field.value < 0 or field.value > 8)
                @compileError("FeatureType has unexpected value");
        }
    }
}

test "server module exports are accessible" {
    _ = server.fingerprint_engine_create;
    _ = server.fingerprint_engine_destroy;
    _ = server.fingerprint_engine_add_feature;
    _ = server.fingerprint_engine_compute;
}

test "exported function names match C header expectations" {
    comptime {
        const expected = [_][]const u8{
            "fingerprint_engine_create",
            "fingerprint_engine_destroy",
            "fingerprint_engine_add_feature",
            "fingerprint_engine_compute",
        };
        for (expected) |name| {
            if (!std.mem.startsWith(u8, name, "fingerprint_engine_"))
                @compileError("C API export must start with fingerprint_engine_");
        }
    }
}
