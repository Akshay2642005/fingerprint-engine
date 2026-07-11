const std = @import("std");
const core = @import("core");

const FeatureID = core.features.FeatureID;
const FeatureType = core.features.FeatureType;
const FeatureValue = core.fingerprint.FeatureValue;
const Feature = core.fingerprint.Feature;
const Fingerprint = core.fingerprint.Fingerprint;

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
        std.sort.block(Feature, ptr.features.items, {}, lessThan);
        core.hashing.hashFingerprintBuffer(ptr.features.items, &digest);
        return digest;
    }

    fn buildFingerprint(ptr: *FingerprintEngine) Fingerprint {
        return .{
            .metadata = .{
                .schema_version = 1,
                .sdk_version = "0.1.0",
                .collected_at = 0,
            },
            .features = ptr.features.items,
        };
    }
};

fn lessThan(_: void, a: Feature, b: Feature) bool {
    return @intFromEnum(a.id) < @intFromEnum(b.id);
}

// ── C-compatible exported API ──

pub export fn fingerprint_engine_create() ?*FingerprintEngine {
    return FingerprintEngine.init(std.heap.page_allocator) catch null;
}

pub export fn fingerprint_engine_destroy(engine: ?*FingerprintEngine) void {
    if (engine) |e| e.deinit();
}

pub export fn fingerprint_engine_add_boolean(
    engine: ?*FingerprintEngine,
    feature_id: i32,
    value: i32,
) void {
    const e = engine orelse return;
    e.addFeature(@enumFromInt(feature_id), .{ .Boolean = value != 0 }) catch return;
}

pub export fn fingerprint_engine_add_integer(
    engine: ?*FingerprintEngine,
    feature_id: i32,
    value: i64,
) void {
    const e = engine orelse return;
    e.addFeature(@enumFromInt(feature_id), .{ .Integer = value }) catch return;
}

pub export fn fingerprint_engine_add_float(
    engine: ?*FingerprintEngine,
    feature_id: i32,
    value: f64,
) void {
    const e = engine orelse return;
    e.addFeature(@enumFromInt(feature_id), .{ .Float = value }) catch return;
}

pub export fn fingerprint_engine_add_string(
    engine: ?*FingerprintEngine,
    feature_id: i32,
    value_data: ?[*]const u8,
    value_len: i32,
) i32 {
    const e = engine orelse return -1;
    const data = value_data orelse return -1;
    const slice = data[0..@as(usize, @intCast(value_len))];
    e.addFeature(@enumFromInt(feature_id), .{ .String = slice }) catch return -1;
    return 0;
}

pub export fn fingerprint_engine_add_bytes(
    engine: ?*FingerprintEngine,
    feature_id: i32,
    value_data: ?[*]const u8,
    value_len: i32,
) i32 {
    const e = engine orelse return -1;
    const data = value_data orelse return -1;
    const slice = data[0..@as(usize, @intCast(value_len))];
    e.addFeature(@enumFromInt(feature_id), .{ .Bytes = slice }) catch return -1;
    return 0;
}

pub export fn fingerprint_engine_compute(
    engine: ?*FingerprintEngine,
    out_digest: ?[*]u8,
) i32 {
    const e = engine orelse return -1;
    const digest_out = out_digest orelse return -1;
    const digest = e.compute() catch return -1;
    @memcpy(digest_out[0..32], &digest);
    return 0;
}

pub export fn fingerprint_engine_normalize(
    engine: ?*FingerprintEngine,
) i32 {
    const e = engine orelse return -1;
    const fp = e.buildFingerprint();

    const type_warns = core.normalization.validateTypes(fp, e.allocator) catch &.{};
    defer e.allocator.free(type_warns);

    const bound_warns = core.normalization.checkAllBounds(fp, e.allocator) catch &.{};
    defer e.allocator.free(bound_warns);

    return @intCast(type_warns.len + bound_warns.len);
}

pub export fn fingerprint_engine_risk(
    engine: ?*FingerprintEngine,
) i32 {
    const e = engine orelse return -1;
    const fp = e.buildFingerprint();
    const assessment = core.risk.computeRisk(fp, e.allocator) catch return -1;
    return @intFromFloat(assessment.score * 100.0);
}

pub export fn fingerprint_engine_entropy(
    engine: ?*FingerprintEngine,
) i32 {
    const e = engine orelse return -1;
    const fp = e.buildFingerprint();
    const entropy = core.entropy.fingerprintEntropy(fp);
    return @intFromFloat(entropy * 100.0);
}
