const std = @import("std");
const fingerprint = @import("model");
const codec = @import("codec.zig");

const Feature = fingerprint.Feature;
const FeatureValue = fingerprint.FeatureValue;
const Fingerprint = fingerprint.Fingerprint;
const FingerprintMetadata = fingerprint.FingerprintMetadata;

const FeatureType = @import("model").FeatureType;
const FeatureID = @import("model").FeatureID;

/// Binary format magic bytes: "FNGR"
const MAGIC = [_]u8{ 'F', 'N', 'G', 'R' };

/// Result of decoding a Fingerprint from binary format.
/// The caller owns the allocated memory.
pub const DecodedFingerprint = struct {
    fingerprint: Fingerprint,
    allocator: std.mem.Allocator,

    pub fn deinit(self: DecodedFingerprint) void {
        // v2 allocates sdk_version; v1 uses a static empty string that must
        // never be freed.
        if (self.fingerprint.metadata.schema_version == codec.schema_version_v2) {
            self.allocator.free(self.fingerprint.metadata.sdk_version);
        }
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
/// The body layout is selected by `metadata.schema_version`: v1 for the
/// legacy layout, v2 for the replay-identity layout (design §5.1). Unknown
/// versions encode the v1 body with their version number preserved — the
/// version gate lives at the decode/engine boundary, not here.
pub fn encode(w: anytype, fp: Fingerprint) !void {
    std.debug.assert(fp.metadata.schema_version != 0);
    std.debug.assert(fp.features.len <= std.math.maxInt(u16));
    try w.writeAll(&MAGIC);
    try w.writeInt(u16, fp.metadata.schema_version, .little);
    switch (fp.metadata.schema_version) {
        codec.schema_version_v2 => try encodeV2Body(w, fp),
        else => try encodeV1Body(w, fp),
    }
}

fn encodeV1Body(w: anytype, fp: Fingerprint) !void {
    try w.writeInt(u16, @as(u16, @intCast(fp.features.len)), .little);
    for (fp.features) |feat| {
        try encodeFeature(w, feat);
    }
}

fn encodeV2Body(w: anytype, fp: Fingerprint) !void {
    try w.writeInt(u16, @as(u16, @intCast(fp.metadata.sdk_version.len)), .little);
    try w.writeAll(fp.metadata.sdk_version);
    try w.writeInt(i64, fp.metadata.collected_at, .little);
    try w.writeAll(&fp.metadata.package_id);
    try encodeV1Body(w, fp);
}

fn encodeFeature(w: anytype, feat: Feature) !void {
    try w.writeInt(u16, @intFromEnum(feat.id), .little);
    try w.writeByte(@intFromEnum(feat.value.valueType()));

    // R-3: payload cap per feature — 4 KiB covers any practical browser
    // fingerprint value (longest: StringArray with many entries). If a
    // feature exceeds this, the fixedBufferStream write will error.
    var payload_buf: [4096]u8 = undefined;
    var pfbs = std.io.fixedBufferStream(&payload_buf);
    var pw = pfbs.writer();
    try writeValuePayload(&pw, feat.value);
    const payload = pfbs.getWritten();

    try w.writeInt(u32, @as(u32, @intCast(payload.len)), .little);
    try w.writeAll(payload);
}

fn writeValuePayload(w: anytype, value: FeatureValue) !void {
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
    InvalidPayload,
    UnsupportedVersion,
    Truncated,
    OutOfMemory,
};

/// Helper: read exactly n bytes, mapping any read error to Truncated.
fn readArray(r: anytype, comptime n: usize) DecodeError![n]u8 {
    return r.readBytesNoEof(n) catch return error.Truncated;
}

/// Helper: read exactly buf.len bytes, mapping any read error to Truncated.
fn readExact(r: anytype, buf: []u8) DecodeError!void {
    return r.readNoEof(buf) catch return error.Truncated;
}

/// Decodes a Fingerprint from binary format.
/// The caller must call `decoded.deinit()` to free allocated memory.
/// v1 (legacy layout) and v2 (replay-identity layout) bodies are supported;
/// any other schema version is rejected before parsing.
pub fn decode(r: anytype, allocator: std.mem.Allocator) DecodeError!DecodedFingerprint {
    const magic = try readArray(r, 4);
    if (!std.mem.eql(u8, &magic, &MAGIC)) return error.InvalidMagic;

    const schema_bytes = try readArray(r, 2);
    const schema_version = std.mem.readInt(u16, &schema_bytes, .little);
    std.debug.assert(schema_version != 0);

    return switch (schema_version) {
        codec.schema_version_v1 => decodeV1(r, allocator),
        codec.schema_version_v2 => decodeV2(r, allocator),
        else => error.UnsupportedVersion,
    };
}

/// v1 body: feature_count u16 | features TLV×N. Metadata fields absent on the
/// wire are fabricated (static empty sdk_version, zero collected_at/package_id).
fn decodeV1(r: anytype, allocator: std.mem.Allocator) DecodeError!DecodedFingerprint {
    const count_bytes = try readArray(r, 2);
    const feature_count = std.mem.readInt(u16, &count_bytes, .little);

    const features_slice = try allocator.alloc(Feature, feature_count);
    errdefer allocator.free(features_slice);

    for (features_slice, 0..) |*feat, i| {
        feat.* = decodeFeature(r, allocator) catch |err| {
            for (0..i) |j| freeFeatureValue(allocator, features_slice[j].value);
            return err;
        };
    }

    return DecodedFingerprint{
        .fingerprint = Fingerprint{
            .metadata = FingerprintMetadata{
                .schema_version = codec.schema_version_v1,
                .sdk_version = "",
                .collected_at = 0,
            },
            .features = features_slice,
        },
        .allocator = allocator,
    };
}

/// v2 body: sdk_version_len u16 | sdk_version | collected_at i64 |
/// package_id [16]u8 | feature_count u16 | features TLV×N (design §5.1).
fn decodeV2(r: anytype, allocator: std.mem.Allocator) DecodeError!DecodedFingerprint {
    const sdk_len_bytes = try readArray(r, 2);
    const sdk_len = std.mem.readInt(u16, &sdk_len_bytes, .little);

    const sdk_version = try allocator.alloc(u8, sdk_len);
    errdefer allocator.free(sdk_version);
    try readExact(r, sdk_version);

    const collected_bytes = try readArray(r, 8);
    const collected_at = std.mem.readInt(i64, &collected_bytes, .little);

    const package_id = try readArray(r, 16);

    const count_bytes = try readArray(r, 2);
    const feature_count = std.mem.readInt(u16, &count_bytes, .little);

    const features_slice = try allocator.alloc(Feature, feature_count);
    errdefer allocator.free(features_slice);

    for (features_slice, 0..) |*feat, i| {
        feat.* = decodeFeature(r, allocator) catch |err| {
            for (0..i) |j| freeFeatureValue(allocator, features_slice[j].value);
            return err;
        };
    }

    return DecodedFingerprint{
        .fingerprint = Fingerprint{
            .metadata = FingerprintMetadata{
                .schema_version = codec.schema_version_v2,
                .sdk_version = sdk_version,
                .collected_at = collected_at,
                .package_id = package_id,
            },
            .features = features_slice,
        },
        .allocator = allocator,
    };
}

fn decodeFeature(r: anytype, allocator: std.mem.Allocator) DecodeError!Feature {
    const id_bytes = try readArray(r, 2);
    const id_int = std.mem.readInt(u16, &id_bytes, .little);

    const type_bytes = try readArray(r, 1);
    const type_tag = type_bytes[0];

    const len_bytes = try readArray(r, 4);
    const payload_len = std.mem.readInt(u32, &len_bytes, .little);

    const payload = try allocator.alloc(u8, payload_len);
    defer allocator.free(payload);
    try readExact(r, payload);

    // BUG-009: validate enum tags from untrusted wire data before use.
    const feature_type = std.meta.intToEnum(FeatureType, type_tag) catch return error.InvalidPayload;

    var pfbs = std.io.fixedBufferStream(payload);
    var pr = pfbs.reader();
    const value = try readValuePayload(&pr, allocator, feature_type);

    const feature_id = std.meta.intToEnum(FeatureID, id_int) catch return error.InvalidPayload;

    return Feature{
        .id = feature_id,
        .value = value,
    };
}

fn readValuePayload(r: anytype, allocator: std.mem.Allocator, tag: FeatureType) DecodeError!FeatureValue {
    switch (tag) {
        .Boolean => {
            const byte = (try readArray(r, 1))[0];
            // R-4: reject non-canonical booleans — payload must be exactly 1 byte.
            if (byte != 0 and byte != 1) return error.InvalidPayload;
            return FeatureValue{ .Boolean = byte == 1 };
        },
        .Integer => {
            const bytes = try readArray(r, 8);
            return FeatureValue{ .Integer = std.mem.readInt(i64, &bytes, .little) };
        },
        .Float => {
            const bytes = try readArray(r, 8);
            const bits = std.mem.readInt(u64, &bytes, .little);
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
                items[i] = std.mem.readInt(i64, &bytes, .little);
            }
            return FeatureValue{ .IntegerArray = items };
        },
        .FloatArray => {
            const count = try readU32(r);
            var items = try allocator.alloc(f64, count);
            errdefer allocator.free(items);
            for (0..count) |i| {
                const bytes = try readArray(r, 8);
                items[i] = @bitCast(std.mem.readInt(u64, &bytes, .little));
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

fn readU32(r: anytype) DecodeError!u32 {
    const bytes = try readArray(r, 4);
    return std.mem.readInt(u32, &bytes, .little);
}
