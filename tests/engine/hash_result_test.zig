const std = @import("std");
const testing = std.testing;
const engine = @import("engine");
const core = @import("core");
const model = @import("model");
const serialization = @import("serialization");
const builders = @import("test_utils").builders;

const Layout = engine.ops.hash.Layout;
const Request = engine.Request;
const Response = engine.Response;

// ADR-013 §3 / `05-two-digest-result-layout.md`: the byte table is the wire
// contract, so pin every offset, width, and total here as well as in the
// engine's comptime guard.
test "fingerprint_result: v2 layout is pinned" {
    try testing.expectEqual(@as(usize, 0), Layout.fingerprint_digest.offset);
    try testing.expectEqual(@as(usize, 32), Layout.fingerprint_digest.len);
    try testing.expectEqual(@as(usize, 32), Layout.feature_count.offset);
    try testing.expectEqual(@as(usize, 2), Layout.feature_count.len);
    try testing.expectEqual(@as(usize, 34), Layout.schema_version.offset);
    try testing.expectEqual(@as(usize, 2), Layout.schema_version.len);

    try testing.expectEqual(@as(usize, 36), Layout.core_digest.offset);
    try testing.expectEqual(@as(usize, 32), Layout.core_digest.len);
    try testing.expectEqual(@as(usize, 68), Layout.core_feature_count.offset);
    try testing.expectEqual(@as(usize, 2), Layout.core_feature_count.len);
    try testing.expectEqual(@as(usize, 70), Layout.core_version.offset);
    try testing.expectEqual(@as(usize, 2), Layout.core_version.len);

    // v1 stays the 36-byte stable prefix; the append adds exactly 36 bytes.
    try testing.expectEqual(@as(usize, 36), Layout.v1_len);
    try testing.expectEqual(@as(usize, 72), Layout.len);
    try testing.expectEqual(Layout.v1_len + 36, Layout.len);
}

test "fingerprint_result: window resize changes full digest but not core digest" {
    const base = [_]model.Feature{
        builders.stringFeature(.UserAgent, "Mozilla/5.0"),
        builders.stringFeature(.Platform, "MacIntel"),
        builders.stringFeature(.Language, "en-US"),
        builders.intFeature(.HardwareConcurrency, 8),
        builders.intFeature(.DeviceMemory, 8),
        builders.intFeature(.ColorDepth, 24),
        builders.intFeature(.ScreenWidth, 1920),
        builders.intFeature(.ScreenHeight, 1080),
        builders.intFeature(.InnerWidth, 1280),
        builders.intFeature(.InnerHeight, 720),
    };
    var resized: [base.len]model.Feature = base;
    resized[8] = builders.intFeature(.InnerWidth, 900);
    resized[9] = builders.intFeature(.InnerHeight, 600);

    const before = try hashFeatures(&base);
    const after = try hashFeatures(&resized);

    // Same feature set and count; only volatile geometry changed.
    try testing.expectEqual(featureCount(&before), featureCount(&after));
    try testing.expectEqual(featureCount(&before), @as(u16, base.len));

    // The identity digest moves...
    try testing.expect(!std.mem.eql(u8, slice(&before, Layout.fingerprint_digest), slice(&after, Layout.fingerprint_digest)));
    // ...while the stable-core digest and its count/version do not.
    try testing.expectEqualSlices(u8, slice(&before, Layout.core_digest), slice(&after, Layout.core_digest));
    try testing.expectEqual(coreCount(&before), coreCount(&after));
    try testing.expectEqual(coreVersion(&before), coreVersion(&after));
}

test "fingerprint_result: core digest matches hashing only the core subset" {
    const feats = [_]model.Feature{
        builders.stringFeature(.UserAgent, "Mozilla/5.0"), // not core
        builders.stringFeature(.Platform, "MacIntel"), // core
        builders.stringFeature(.Language, "en-US"), // core
        builders.intFeature(.HardwareConcurrency, 8), // core
        builders.intFeature(.DeviceMemory, 8), // core
        builders.intFeature(.ColorDepth, 24), // core
        builders.intFeature(.ScreenWidth, 1920), // not core
        builders.intFeature(.InnerWidth, 1280), // not core
    };

    var core_only: [feats.len]model.Feature = undefined;
    var n: usize = 0;
    for (feats) |feat| {
        if (!model.Registry.isCore(feat.id)) continue;
        core_only[n] = feat;
        n += 1;
    }
    // The engine canonicalizes before hashing; mirror that so the expected
    // digest is computed over the same (sorted) core list.
    std.mem.sort(model.Feature, core_only[0..n], {}, struct {
        fn lessThan(_: void, a: model.Feature, b: model.Feature) bool {
            return @intFromEnum(a.id) < @intFromEnum(b.id);
        }
    }.lessThan);

    var expected: [32]u8 = undefined;
    core.hashing.hashFingerprintBuffer(core_only[0..n], &expected);

    const result = try hashFeatures(&feats);
    try testing.expectEqualSlices(u8, &expected, slice(&result, Layout.core_digest));
    try testing.expectEqual(@as(u16, @intCast(n)), coreCount(&result));
    try testing.expectEqual(model.Registry.core_version, coreVersion(&result));
}

test "fingerprint_result: core digest is deterministic for a pinned fixture" {
    // Golden pin for the core digest: a change here means either the hashing
    // composition or the core subset changed, which must be a deliberate
    // (core_version-bumping) decision — see `07-stable-core-subset.md`.
    const feats = [_]model.Feature{
        builders.stringFeature(.Platform, "MacIntel"),
        builders.stringFeature(.Language, "en-US"),
        builders.intFeature(.HardwareConcurrency, 8),
        builders.intFeature(.ColorDepth, 24),
        builders.stringFeature(.Timezone, "UTC"),
    };

    const result = try hashFeatures(&feats);

    // Golden pin for the core digest. A change here means either the hashing
    // composition or the core subset changed, which must be a deliberate
    // (core_version-bumping) decision — see `07-stable-core-subset.md`.
    const expected_hex = "6d6e8d725fce0be4d477e4a6f36b2670c362db181b421502cb8106a125bb062f";
    var hex: [64]u8 = undefined;
    const actual = try std.fmt.bufPrint(&hex, "{s}", .{
        std.fmt.fmtSliceHexLower(slice(&result, Layout.core_digest)),
    });
    try testing.expectEqualStrings(expected_hex, actual);

    try testing.expectEqual(@as(u16, feats.len), coreCount(&result));
    try testing.expectEqual(@as(u16, 1), coreVersion(&result));
}

test "fingerprint_result: no core features yields the empty-input digest" {
    const feats = [_]model.Feature{
        builders.stringFeature(.UserAgent, "Mozilla/5.0"),
        builders.intFeature(.InnerWidth, 1280),
    };

    const result = try hashFeatures(&feats);
    // SHA-256 over an empty byte stream: the core feature list is empty.
    const empty_digest = [_]u8{
        0xe3, 0xb0, 0xc4, 0x42, 0x98, 0xfc, 0x1c, 0x14,
        0x9a, 0xfb, 0xf4, 0xc8, 0x99, 0x6f, 0xb9, 0x24,
        0x27, 0xae, 0x41, 0xe4, 0x64, 0x9b, 0x93, 0x4c,
        0xa4, 0x95, 0x99, 0x1b, 0x78, 0x52, 0xb8, 0x55,
    };
    try testing.expectEqualSlices(u8, &empty_digest, slice(&result, Layout.core_digest));
    try testing.expectEqual(@as(u16, 0), coreCount(&result));
}

test "fingerprint_result: a 36-byte v1 reader sees the legacy prefix unchanged" {
    const feats = [_]model.Feature{
        builders.stringFeature(.UserAgent, "Mozilla/5.0"),
        builders.stringFeature(.Language, "en-US"),
    };

    const result = try hashFeatures(&feats);
    var expected_full: [32]u8 = undefined;
    core.hashing.hashFingerprintBuffer(&feats, &expected_full);

    // The legacy 36-byte read is byte-identical to hashing the same features
    // with the v1 routine.
    try testing.expectEqualSlices(u8, &expected_full, result[0..32]);
    try testing.expectEqual(@as(u16, feats.len), std.mem.readInt(u16, result[32..34], .little));
    try testing.expectEqual(@as(u16, 1), std.mem.readInt(u16, result[34..36], .little));
}

fn hashFeatures(feats: []const model.Feature) ![Layout.len]u8 {
    var arena_instance = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    const fp = builders.makeFingerprint(feats);
    var payload_buf: [2048]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&payload_buf);
    try serialization.encode(fbs.writer(), fp);

    var response_buf: [512]u8 = undefined;
    const req = Request{ .operation = .hash, .codec = .binary, .payload = fbs.getWritten() };
    var res = Response.init(.hash, &response_buf);
    try engine.process(&req, &res, arena);

    try testing.expectEqual(engine.Status.ok, res.status);
    try testing.expectEqual(Layout.len, res.payload_len);

    var out: [Layout.len]u8 = undefined;
    @memcpy(&out, res.slice());
    return out;
}

fn slice(result: []const u8, field: Layout.Field) []const u8 {
    return result[field.offset..][0..field.len];
}

fn featureCount(result: []const u8) u16 {
    return std.mem.readInt(u16, result[Layout.feature_count.offset..][0..2], .little);
}

fn coreCount(result: []const u8) u16 {
    return std.mem.readInt(u16, result[Layout.core_feature_count.offset..][0..2], .little);
}

fn coreVersion(result: []const u8) u16 {
    return std.mem.readInt(u16, result[Layout.core_version.offset..][0..2], .little);
}
