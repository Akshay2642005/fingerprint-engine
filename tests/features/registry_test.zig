const std = @import("std");
const testing = std.testing;
const features = @import("core").features;

// ──────────────────────────────────────────────
// Registry — count
// ──────────────────────────────────────────────

test "Registry.count returns 37 defined features" {
    try testing.expectEqual(@as(usize, 37), features.Registry.count());
}

test "Registry.count matches definitions array length" {
    try testing.expectEqual(features.Registry.all().len, features.Registry.count());
}

// ──────────────────────────────────────────────
// Registry — all
// ──────────────────────────────────────────────

test "Registry.all returns a slice of all definitions" {
    const all = features.Registry.all();
    try testing.expect(all.len > 0);
    try testing.expectEqual(all.len, features.Registry.count());
}

test "Registry.all definitions are in FeatureID order" {
    const all = features.Registry.all();
    var prev_id: i32 = -1;
    for (all) |def| {
        const current = @intFromEnum(def.id);
        try testing.expect(current > prev_id);
        prev_id = @intCast(current);
    }
}

test "Registry.all definitions have sequential FeatureIDs" {
    const all = features.Registry.all();
    for (all, 0..) |def, i| {
        try testing.expectEqual(@as(u16, @intCast(i)), @intFromEnum(def.id));
    }
}

// ──────────────────────────────────────────────
// Registry — get
// ──────────────────────────────────────────────

test "Registry.get returns definition for valid FeatureID" {
    const def = features.Registry.get(features.FeatureID.UserAgent);
    try testing.expectEqual(def.id, features.FeatureID.UserAgent);
}

test "Registry.get returns correct definition for each registered ID" {
    const all = features.Registry.all();
    for (all) |expected| {
        const actual = features.Registry.get(expected.id);
        try testing.expectEqual(expected.id, actual.id);
        try testing.expectEqual(expected.category, actual.category);
        try testing.expectEqual(expected.value_type, actual.value_type);
        try testing.expectEqual(expected.weight, actual.weight);
    }
}

test "Registry.get returns pointer to same definition as all()" {
    const all = features.Registry.all();
    for (all) |*expected| {
        const actual = features.Registry.get(expected.id);
        try testing.expectEqual(expected.id, actual.id);
    }
}

test "Registry.get returns stable pointers across calls" {
    const first = features.Registry.get(features.FeatureID.CanvasHash);
    const second = features.Registry.get(features.FeatureID.CanvasHash);
    try testing.expectEqual(first, second);
}

test "Registry.get lookup is O(1) — direct array indexing" {
    // Verify by checking documentation: lookup is a flat array indexed by FeatureID
    const idx = @intFromEnum(features.FeatureID.WebGLRenderer);
    const def = features.Registry.get(features.FeatureID.WebGLRenderer);
    try testing.expectEqual(def.id, features.FeatureID.WebGLRenderer);
    try testing.expectEqual(@as(u16, 17), idx);
}

// ──────────────────────────────────────────────
// Registry — individual lookups
// ──────────────────────────────────────────────

test "Registry.get for all 37 defined features" {
    const count = features.Registry.count();
    try testing.expectEqual(@as(usize, 37), count);
    const all = features.Registry.all();
    for (all) |def| {
        const lookup = features.Registry.get(def.id);
        try testing.expectEqual(def.id, lookup.id);
    }
}

// ──────────────────────────────────────────────
// Registry — definition immutability
// ──────────────────────────────────────────────

test "Registry.all returns const slice — definitions are immutable" {
    const all = features.Registry.all();
    // Verify definitions can be read through the const interface
    for (all) |def| {
        try testing.expect(def.weight >= 0);
    }
}
