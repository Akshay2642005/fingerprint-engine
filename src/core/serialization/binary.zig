const std = @import("std");
const fingerprint = @import("../fingerprint/root.zig");

const Feature = fingerprint.Feature;
const FeatureValue = fingerprint.FeatureValue;
const Fingerprint = fingerprint.Fingerprint;

const FeatureType = @import("../features/model.zig").FeatureType;

/// Binary format magic bytes: "FNGR"
const MAGIC = [_]u8{ 'F', 'N', 'G', 'R' };

/// Encodes a Fingerprint into binary format using the provided writer.
///
/// Format:
///   Header: magic(4) | schema_version(2 LE) | feature_count(2 LE)
///   For each feature: id(2 LE) | type(1) | payload_len(4 LE) | payload(N)
pub fn encode(w: *std.Io.Writer, fp: Fingerprint) !void {
    // Header
    try w.writeAll(&MAGIC);
    try w.writeInt(u16, fp.metadata.schema_version, .little);
    try w.writeInt(u16, @as(u16, @intCast(fp.features.len)), .little);

    // Features
    for (fp.features) |feat| {
        try encodeFeature(w, feat);
    }
}

fn encodeFeature(w: *std.Io.Writer, feat: Feature) !void {
    try w.writeInt(u16, @intFromEnum(feat.id), .little);
    try w.writeByte(@intFromEnum(feat.value.valueType()));

    // Encode value payload into a temp buffer first to know its length
    var payload_buf: [1024]u8 = undefined;
    var pw = std.Io.Writer.fixed(&payload_buf);
    try writeValuePayload(&pw, feat.value);
    const payload = payload_buf[0..pw.end];

    try w.writeInt(u32, @as(u32, @intCast(payload.len)), .little);
    try w.writeAll(payload);
}

fn writeValuePayload(w: *std.Io.Writer, value: FeatureValue) !void {
    switch (value) {
        .Boolean => |v| try w.writeByte(if (v) 1 else 0),
        .Integer => |v| try w.writeInt(i64, v, .little),
        .Float => |v| try w.writeInt(u64, @bitCast(v), .little),
        .String => |v| {
            try w.writeInt(u32, @as(u32, @intCast(v.len)), .little);
            try w.writeAll(v);
        },
        .Bytes => |v| {
            try w.writeInt(u32, @as(u32, @intCast(v.len)), .little);
            try w.writeAll(v);
        },
        .StringArray => |v| {
            try w.writeInt(u32, @as(u32, @intCast(v.len)), .little);
            for (v) |item| {
                try w.writeInt(u32, @as(u32, @intCast(item.len)), .little);
                try w.writeAll(item);
            }
        },
        .IntegerArray => |v| {
            try w.writeInt(u32, @as(u32, @intCast(v.len)), .little);
            for (v) |item| {
                try w.writeInt(i64, item, .little);
            }
        },
        .FloatArray => |v| {
            try w.writeInt(u32, @as(u32, @intCast(v.len)), .little);
            for (v) |item| {
                try w.writeInt(u64, @bitCast(item), .little);
            }
        },
        .BytesArray => |v| {
            try w.writeInt(u32, @as(u32, @intCast(v.len)), .little);
            for (v) |item| {
                try w.writeInt(u32, @as(u32, @intCast(item.len)), .little);
                try w.writeAll(item);
            }
        },
    }
}
