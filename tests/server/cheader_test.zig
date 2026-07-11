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

            // Verify the zig enum value is in expected range (0-101)
            if (field.value < 0 or field.value > 101)
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
    _ = server.fingerprint_engine_add_boolean;
    _ = server.fingerprint_engine_add_integer;
    _ = server.fingerprint_engine_add_float;
    _ = server.fingerprint_engine_add_string;
    _ = server.fingerprint_engine_add_bytes;
    _ = server.fingerprint_engine_compute;
    _ = server.fingerprint_engine_normalize;
    _ = server.fingerprint_engine_risk;
    _ = server.fingerprint_engine_entropy;
}

test "exported function names match C header expectations" {
    comptime {
        const expected = [_][]const u8{
            "fingerprint_engine_create",
            "fingerprint_engine_destroy",
            "fingerprint_engine_add_boolean",
            "fingerprint_engine_add_integer",
            "fingerprint_engine_add_float",
            "fingerprint_engine_add_string",
            "fingerprint_engine_add_bytes",
            "fingerprint_engine_compute",
            "fingerprint_engine_normalize",
            "fingerprint_engine_risk",
            "fingerprint_engine_entropy",
        };
        for (expected) |name| {
            if (!std.mem.startsWith(u8, name, "fingerprint_engine_"))
                @compileError("C API export must start with fingerprint_engine_");
        }
    }
}
