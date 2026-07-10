const std = @import("std");
const fingerprint = @import("../fingerprint/root.zig");

const Feature = fingerprint.Feature;
const FeatureValue = fingerprint.FeatureValue;
const Fingerprint = fingerprint.Fingerprint;
const FingerprintMetadata = fingerprint.FingerprintMetadata;

const FeatureType = @import("../features/model.zig").FeatureType;

/// Binary format magic bytes: "FNGR"
const MAGIC = [_]u8{ 'F', 'N', 'G', 'R' };

/// Result of decoding a Fingerprint from binary format.
/// The caller owns the allocated memory.
pub const DecodedFingerprint = struct {
    fingerprint: Fingerprint,
    allocator: std.mem.Allocator,

    pub fn deinit(self: DecodedFingerprint) void {
        for (self.fingerprint.features) |feat| {
            freeFeatureValue(self.allocator, feat.value);
        }
        self.allocator.free(self.fingerprint.features);
    }
};

fn freeFeatureValue(allocator: std.mem.Allocator, value: FeatureValue) void {
    switch (value) {
        .String => |v| allocator.free(v),
        .Bytes => |v| allocator.free(v),
        .StringArray => |v| {
            for (v) |item| allocator.free(item);
            allocator.free(v);
        },
        .IntegerArray => |v| allocator.free(v),
        .FloatArray => |v| allocator.free(v),
        .BytesArray => |v| {
            for (v) |item| allocator.free(item);
            allocator.free(v);
        },
        else => {},
    }
}

/// Encodes a Fingerprint into binary format using the provided writer.
pub fn encode(w: *std.Io.Writer, fp: Fingerprint) !void {
    try w.writeAll(&MAGIC);
    try w.writeInt(u16, fp.metadata.schema_version, .little);
    try w.writeInt(u16, @as(u16, @intCast(fp.features.len)), .little);

    for (fp.features) |feat| {
        try encodeFeature(w, feat);
    }
}

fn encodeFeature(w: *std.Io.Writer, feat: Feature) !void {
    try w.writeInt(u16, @intFromEnum(feat.id), .little);
    try w.writeByte(@intFromEnum(feat.value.valueType()));

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
            for (v) |item| try w.writeInt(i64, item, .little);
        },
        .FloatArray => |v| {
            try w.writeInt(u32, @as(u32, @intCast(v.len)), .little);
            for (v) |item| try w.writeInt(u64, @bitCast(item), .little);
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

// ──────────────────────────────────────────────
// Decode
// ──────────────────────────────────────────────

pub const DecodeError = error{
    InvalidMagic,
    Truncated,
    OutOfMemory,
};

/// Helper: wrap takeArray to convert EndOfStream/ReadFailed to Truncated.
fn readArray(r: *std.Io.Reader, comptime n: usize) DecodeError!*[n]u8 {
    return r.takeArray(n) catch |err| switch (err) {
        error.EndOfStream => return error.Truncated,
        error.ReadFailed => return error.Truncated,
    };
}

/// Helper: wrap readSliceAll to convert EndOfStream/ReadFailed to Truncated.
fn readExact(r: *std.Io.Reader, buf: []u8) DecodeError!void {
    return r.readSliceAll(buf) catch |err| switch (err) {
        error.EndOfStream => return error.Truncated,
        error.ReadFailed => return error.Truncated,
    };
}

/// Decodes a Fingerprint from binary format.
/// The caller must call `decoded.deinit()` to free allocated memory.
pub fn decode(r: *std.Io.Reader, allocator: std.mem.Allocator) DecodeError!DecodedFingerprint {
    const magic = try readArray(r, 4);
    if (!std.mem.eql(u8, magic, &MAGIC)) return error.InvalidMagic;

    const schema_bytes = try readArray(r, 2);
    const schema_version = std.mem.readInt(u16, schema_bytes, .little);

    const count_bytes = try readArray(r, 2);
    const feature_count = std.mem.readInt(u16, count_bytes, .little);

    const features_slice = try allocator.alloc(Feature, feature_count);
    errdefer allocator.free(features_slice);

    for (features_slice, 0..) |*feat, i| {
        feat.* = decodeFeature(r, allocator) catch |err| {
            for (0..i) |j| freeFeatureValue(allocator, features_slice[j].value);
            return err;
        };
    }

    const meta = FingerprintMetadata{
        .schema_version = schema_version,
        .sdk_version = "",
        .collected_at = 0,
    };

    return DecodedFingerprint{
        .fingerprint = Fingerprint{
            .metadata = meta,
            .features = features_slice,
        },
        .allocator = allocator,
    };
}

fn decodeFeature(r: *std.Io.Reader, allocator: std.mem.Allocator) DecodeError!Feature {
    const id_bytes = try readArray(r, 2);
    const id_int = std.mem.readInt(u16, id_bytes, .little);

    const type_bytes = try readArray(r, 1);
    const type_tag = type_bytes[0];

    const len_bytes = try readArray(r, 4);
    const payload_len = std.mem.readInt(u32, len_bytes, .little);

    const payload = try allocator.alloc(u8, payload_len);
    defer allocator.free(payload);
    try readExact(r, payload);

    var pr = std.Io.Reader.fixed(payload);
    const value = try readValuePayload(&pr, allocator, @enumFromInt(type_tag));

    return Feature{
        .id = @enumFromInt(id_int),
        .value = value,
    };
}

fn readValuePayload(r: *std.Io.Reader, allocator: std.mem.Allocator, tag: FeatureType) DecodeError!FeatureValue {
    switch (tag) {
        .Boolean => {
            const byte = (try readArray(r, 1))[0];
            return FeatureValue{ .Boolean = byte != 0 };
        },
        .Integer => {
            const bytes = try readArray(r, 8);
            return FeatureValue{ .Integer = std.mem.readInt(i64, bytes, .little) };
        },
        .Float => {
            const bytes = try readArray(r, 8);
            const bits = std.mem.readInt(u64, bytes, .little);
            return FeatureValue{ .Float = @bitCast(bits) };
        },
        .String => {
            const len = try readU32(r);
            const bytes = try allocator.alloc(u8, len);
            try readExact(r, bytes);
            return FeatureValue{ .String = bytes };
        },
        .Bytes => {
            const len = try readU32(r);
            const bytes = try allocator.alloc(u8, len);
            try readExact(r, bytes);
            return FeatureValue{ .Bytes = bytes };
        },
        .StringArray => {
            const count = try readU32(r);
            var items = try allocator.alloc([]const u8, count);
            errdefer allocator.free(items);
            for (0..count) |i| {
                const item_len = try readU32(r);
                const item = try allocator.alloc(u8, item_len);
                try readExact(r, item);
                items[i] = item;
            }
            return FeatureValue{ .StringArray = items };
        },
        .IntegerArray => {
            const count = try readU32(r);
            var items = try allocator.alloc(i64, count);
            errdefer allocator.free(items);
            for (0..count) |i| {
                const bytes = try readArray(r, 8);
                items[i] = std.mem.readInt(i64, bytes, .little);
            }
            return FeatureValue{ .IntegerArray = items };
        },
        .FloatArray => {
            const count = try readU32(r);
            var items = try allocator.alloc(f64, count);
            errdefer allocator.free(items);
            for (0..count) |i| {
                const bytes = try readArray(r, 8);
                items[i] = @bitCast(std.mem.readInt(u64, bytes, .little));
            }
            return FeatureValue{ .FloatArray = items };
        },
        .BytesArray => {
            const count = try readU32(r);
            var items = try allocator.alloc([]const u8, count);
            errdefer allocator.free(items);
            for (0..count) |i| {
                const item_len = try readU32(r);
                const item = try allocator.alloc(u8, item_len);
                try readExact(r, item);
                items[i] = item;
            }
            return FeatureValue{ .BytesArray = items };
        },
    }
}

fn readU32(r: *std.Io.Reader) DecodeError!u32 {
    const bytes = try readArray(r, 4);
    return std.mem.readInt(u32, bytes, .little);
}
