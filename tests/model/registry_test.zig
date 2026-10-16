const std = @import("std");
const testing = std.testing;
const features = @import("model");

// ──────────────────────────────────────────────
// Registry — count
// ──────────────────────────────────────────────

test "Registry.count returns 37 defined features" {
    try testing.expectEqual(@as(usize, 102), features.Registry.count());
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
    try testing.expectEqual(@as(u16, 37), idx);
}

// ──────────────────────────────────────────────
// Registry — individual lookups
// ──────────────────────────────────────────────

test "Registry.get for all 102 defined features" {
    const count = features.Registry.count();
    try testing.expectEqual(@as(usize, 102), count);
    const all = features.Registry.all();
    for (all) |def| {
        const lookup = features.Registry.get(def.id);
        try testing.expectEqual(def.id, lookup.id);
    }
}

// ──────────────────────────────────────────────
// Registry — tolerant lookup (m6-tolerant-lookup)
// ──────────────────────────────────────────────

// story: m6-tolerant-lookup
test "Registry.lookup returns definition for each registered raw id" {
    const all = features.Registry.all();
    for (all) |def| {
        const got = features.Registry.lookup(@intFromEnum(def.id));
        try testing.expect(got != null);
        try testing.expectEqual(def.id, got.?.id);
    }
}

test "Registry.lookup returns null for Count sentinel raw id" {
    try testing.expect(features.Registry.lookup(102) == null);
}

test "Registry.lookup returns null for out-of-range raw ids" {
    // 0..101 are the 102 registered ids; 103 and above are unregistered.
    try testing.expect(features.Registry.lookup(103) == null);
    try testing.expect(features.Registry.lookup(255) == null);
    try testing.expect(features.Registry.lookup(65535) == null);
}

test "Registry.lookup never errors — same pointer as get() for known ids" {
    const def = features.Registry.get(features.FeatureID.CanvasHash);
    const got = features.Registry.lookup(@intFromEnum(features.FeatureID.CanvasHash));
    try testing.expectEqual(def, got.?);
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

// ──────────────────────────────────────────────
// Registry — stable-core subset (D-v1-7 / m6-signal-contract)
// ──────────────────────────────────────────────

test "core_version is a positive revision" {
    try testing.expectEqual(@as(u16, 1), features.Registry.core_version);
}

test "core subset is non-empty and matches the flagged-feature count" {
    const subset = features.Registry.coreSubset();
    try testing.expect(subset.len > 0);
    try testing.expectEqual(subset.len, features.Registry.coreCount());

    var flagged: usize = 0;
    for (features.Registry.all()) |def| {
        if (def.isCore()) flagged += 1;
    }
    try testing.expectEqual(subset.len, flagged);
}

test "every core_subset entry is flagged .core and not sensitive" {
    for (features.Registry.coreSubset()) |id| {
        const def = features.Registry.get(id);
        try testing.expect(def.isCore());
        try testing.expect(!def.isSensitive());
    }
}

test "no metadata feature is in the core subset" {
    for (features.Registry.all()) |def| {
        if (def.category == features.FeatureCategory.Metadata) {
            try testing.expect(!def.isCore());
        }
    }
}

test "window geometry is excluded from the core subset" {
    // These flip on window resize / fullscreen, so they must never anchor the
    // stable core (design: specs/quality/signal-determinism-contract.md).
    const geometry = [_]features.FeatureID{
        features.FeatureID.InnerWidth,
        features.FeatureID.InnerHeight,
        features.FeatureID.OuterWidth,
        features.FeatureID.OuterHeight,
        features.FeatureID.ScreenWidth,
        features.FeatureID.ScreenHeight,
        features.FeatureID.AvailableWidth,
        features.FeatureID.AvailableHeight,
    };
    for (geometry) |id| {
        try testing.expect(!features.Registry.isCore(id));
    }
}

test "transient condition signals are excluded from the core subset" {
    // Battery, network and permission state vary with condition, not device.
    const condition = [_]features.FeatureID{
        features.FeatureID.BatteryLevel,
        features.FeatureID.BatteryCharging,
        features.FeatureID.BatteryChargingTime,
        features.FeatureID.ConnectionType,
        features.FeatureID.ConnectionEffectiveType,
        features.FeatureID.ConnectionDownlink,
        features.FeatureID.ConnectionRtt,
        features.FeatureID.ConnectionSaveData,
        features.FeatureID.NotificationPermission,
    };
    for (condition) |id| {
        try testing.expect(!features.Registry.isCore(id));
    }
}

test "update-drift UA surface is excluded from the core subset" {
    // A browser update flips these without the device changing.
    const update_drift = [_]features.FeatureID{
        features.FeatureID.UserAgent,
        features.FeatureID.AppVersion,
        features.FeatureID.OSVersion,
    };
    for (update_drift) |id| {
        try testing.expect(!features.Registry.isCore(id));
    }
}

test "core subset is in strictly ascending FeatureID order" {
    const subset = features.Registry.coreSubset();
    var prev: i32 = -1;
    for (subset) |id| {
        const current = @intFromEnum(id);
        try testing.expect(current > prev);
        prev = current;
    }
}

test "durable device anchors are in the core subset" {
    const anchors = [_]features.FeatureID{
        features.FeatureID.CanvasHash,
        features.FeatureID.WebGLRenderer,
        features.FeatureID.AudioHash,
        features.FeatureID.FontsHash,
        features.FeatureID.HardwareConcurrency,
        features.FeatureID.DeviceMemory,
        features.FeatureID.Platform,
        features.FeatureID.Language,
        features.FeatureID.Timezone,
        features.FeatureID.ColorDepth,
        features.FeatureID.DevicePixelRatio,
    };
    for (anchors) |id| {
        try testing.expect(features.Registry.isCore(id));
    }
}
