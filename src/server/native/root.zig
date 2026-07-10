const std = @import("std");
const core = @import("core");

const FeatureID = core.features.FeatureID;
const FeatureType = core.features.FeatureType;
const FeatureValue = core.fingerprint.FeatureValue;
const Feature = core.fingerprint.Feature;

/// Opaque engine handle.
pub const FingerprintEngine = struct {
    allocator: std.mem.Allocator,
    features: std.ArrayListUnmanaged(Feature) = .empty,

    fn init(allocator: std.mem.Allocator) !*FingerprintEngine {
        const ptr = try allocator.create(FingerprintEngine);
        ptr.* = .{ .allocator = allocator };
        return ptr;
    }

    fn deinit(ptr: *FingerprintEngine) void {
        ptr.features.deinit(ptr.allocator);
        ptr.allocator.destroy(ptr);
    }

    fn addFeature(ptr: *FingerprintEngine, id: FeatureID, value: FeatureValue) !void {
        try ptr.features.append(ptr.allocator, Feature{ .id = id, .value = value });
    }

    fn compute(ptr: *FingerprintEngine) ![32]u8 {
        var digest: [32]u8 = undefined;
        // Sort features by FeatureID for deterministic output
        std.sort.block(Feature, ptr.features.items, {}, lessThan);
        core.hashing.hashFingerprintBuffer(ptr.features.items, &digest);
        return digest;
    }
};

fn lessThan(_: void, a: Feature, b: Feature) bool {
    return @intFromEnum(a.id) < @intFromEnum(b.id);
}

// ── C-compatible exported API ──

/// Creates a new fingerprint engine instance.
/// Returns an opaque pointer (null on allocation failure).
pub export fn fingerprint_engine_create() ?*FingerprintEngine {
    const allocator = std.heap.page_allocator;
    return FingerprintEngine.init(allocator) catch null;
}

/// Destroys a fingerprint engine instance and frees all associated memory.
pub export fn fingerprint_engine_destroy(engine: ?*FingerprintEngine) void {
    if (engine) |e| e.deinit();
}

/// Adds a feature to the engine.
///
/// Parameters:
/// - engine: Handle returned by fingerprint_engine_create.
/// - feature_id: FeatureID enum value as integer.
/// - value_type: FeatureType enum value as integer.
/// - value_data: Pointer to the raw feature value bytes.
/// - value_len: Length of the value data in bytes.
///
/// Returns 0 on success, -1 on failure.
pub export fn fingerprint_engine_add_feature(
    engine: ?*FingerprintEngine,
    feature_id: i32,
    value_type: i32,
    value_data: ?[*]const u8,
    value_len: i32,
) i32 {
    const e = engine orelse return -1;
    const data = value_data orelse return -1;
    const data_slice = data[0..@as(usize, @intCast(value_len))];

    const id = @as(FeatureID, @enumFromInt(feature_id));
    const ftype = @as(FeatureType, @enumFromInt(value_type));

    const value = deserializeValue(ftype, data_slice) catch return -1;
    e.addFeature(id, value) catch return -1;
    return 0;
}

/// Computes the fingerprint digest (SHA-256) for all added features.
///
/// Parameters:
/// - engine: Handle returned by fingerprint_engine_create.
/// - out_digest: Output buffer for the 32-byte digest.
/// - out_len: On input, max buffer size. On output, actual digest length.
///
/// Returns 0 on success, -1 on failure.
pub export fn fingerprint_engine_compute(
    engine: ?*FingerprintEngine,
    out_digest: ?[*]u8,
    out_len: ?*i32,
) i32 {
    const e = engine orelse return -1;
    const digest_out = out_digest orelse return -1;
    const len_out = out_len orelse return -1;

    const digest = e.compute() catch return -1;
    @memcpy(digest_out[0..32], &digest);
    len_out.* = 32;
    return 0;
}

// ── Value deserialization ──

fn deserializeValue(ftype: FeatureType, data: []const u8) !FeatureValue {
    switch (ftype) {
        .Boolean => {
            if (data.len < 1) return error.InvalidValue;
            return FeatureValue{ .Boolean = data[0] != 0 };
        },
        .Integer => {
            if (data.len < 8) return error.InvalidValue;
            const val = std.mem.readInt(i64, data[0..8], .little);
            return FeatureValue{ .Integer = val };
        },
        .Float => {
            if (data.len < 8) return error.InvalidValue;
            const bits = std.mem.readInt(u64, data[0..8], .little);
            return FeatureValue{ .Float = @bitCast(bits) };
        },
        .String => return FeatureValue{ .String = data },
        .Bytes => return FeatureValue{ .Bytes = data },
        .StringArray => return FeatureValue{ .StringArray = &.{} },
        .IntegerArray => return FeatureValue{ .IntegerArray = &.{} },
        .FloatArray => return FeatureValue{ .FloatArray = &.{} },
        .BytesArray => return FeatureValue{ .BytesArray = &.{} },
    }
}
