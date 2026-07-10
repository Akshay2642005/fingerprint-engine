const std = @import("std");
const fingerprint = @import("../fingerprint/root.zig");

const Feature = fingerprint.Feature;
const FeatureValue = fingerprint.FeatureValue;
const Fingerprint = fingerprint.Fingerprint;

const Registry = @import("../features/registry.zig").Registry;

/// Encodes a Fingerprint as JSON using the provided writer.
pub fn jsonEncode(w: *std.Io.Writer, fp: Fingerprint) !void {
    try w.writeAll("{\n");

    // Metadata fields
    try w.print("  \"schema_version\": {},\n", .{fp.metadata.schema_version});
    try writeJsonString(w, "sdk_version");
    try w.print(": ", .{});
    try writeJsonString(w, fp.metadata.sdk_version);
    try w.writeAll(",\n");
    try w.print("  \"collected_at\": {},\n", .{fp.metadata.collected_at});

    // Features object
    try w.writeAll("  \"features\": {\n");
    for (fp.features, 0..) |feat, i| {
        if (i > 0) try w.writeAll(",\n");
        try w.writeAll("    ");
        const def = Registry.get(feat.id);
        try writeJsonString(w, def.name);
        try w.writeAll(": ");
        try writeJsonValue(w, feat.value);
    }
    if (fp.features.len > 0) try w.writeAll("\n");
    try w.writeAll("  }\n");
    try w.writeAll("}");
}

fn writeJsonValue(w: *std.Io.Writer, value: FeatureValue) !void {
    switch (value) {
        .Boolean => |v| try w.writeAll(if (v) "true" else "false"),
        .Integer => |v| try w.print("{}", .{v}),
        .Float => |v| try w.print("{d}", .{v}),
        .String => |v| try writeJsonString(w, v),
        .Bytes => {
            try w.writeAll("\"");
            for (value.Bytes) |byte| try w.print("\\x{x:0>2}", .{byte});
            try w.writeAll("\"");
        },
        .StringArray => |v| {
            try w.writeAll("[");
            for (v, 0..) |item, i| {
                if (i > 0) try w.writeAll(", ");
                try writeJsonString(w, item);
            }
            try w.writeAll("]");
        },
        .IntegerArray => |v| {
            try w.writeAll("[");
            for (v, 0..) |item, i| {
                if (i > 0) try w.writeAll(", ");
                try w.print("{}", .{item});
            }
            try w.writeAll("]");
        },
        .FloatArray => |v| {
            try w.writeAll("[");
            for (v, 0..) |item, i| {
                if (i > 0) try w.writeAll(", ");
                try w.print("{d}", .{item});
            }
            try w.writeAll("]");
        },
        .BytesArray => |v| {
            try w.writeAll("[");
            for (v, 0..) |item, i| {
                if (i > 0) try w.writeAll(", ");
                try w.writeAll("\"");
                for (item) |byte| try w.print("\\x{x:0>2}", .{byte});
                try w.writeAll("\"");
            }
            try w.writeAll("]");
        },
    }
}

/// Writes a JSON-escaped string (with quotes).
fn writeJsonString(w: *std.Io.Writer, s: []const u8) !void {
    try w.writeAll("\"");
    for (s) |c| {
        switch (c) {
            '"' => try w.writeAll("\\\""),
            '\\' => try w.writeAll("\\\\"),
            '\n' => try w.writeAll("\\n"),
            '\r' => try w.writeAll("\\r"),
            '\t' => try w.writeAll("\\t"),
            0x00...0x08, 0x0B, 0x0C, 0x0E...0x1F => try w.print("\\u{x:0>4}", .{c}),
            else => try w.writeByte(c),
        }
    }
    try w.writeAll("\"");
}
