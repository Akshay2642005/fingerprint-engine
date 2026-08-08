const std = @import("std");
const browser_package = @import("browser_package");

test "packageVersion parses the version field" {
    const alloc = std.testing.allocator;
    const version = try browser_package.packageVersion(alloc, "{\"name\":\"x\",\"version\":\"0.1.2\"}");
    defer alloc.free(version);
    try std.testing.expectEqualStrings("0.1.2", version);
}

test "buildTables covers every signal and skips the Count sentinel" {
    const alloc = std.testing.allocator;
    const tables = try browser_package.buildTables(alloc);
    defer alloc.free(tables);

    // First, last, and a middle signal, plus the FeatureType table.
    try std.testing.expect(std.mem.indexOf(u8, tables, "UserAgent: 0,") != null);
    try std.testing.expect(std.mem.indexOf(u8, tables, "IndexedDB: 49,") != null);
    try std.testing.expect(std.mem.indexOf(u8, tables, "CollectionTimestamp: 101,") != null);
    try std.testing.expect(std.mem.indexOf(u8, tables, "BytesArray: 8,") != null);
    // The internal sentinel must never leak into the TS surface.
    try std.testing.expect(std.mem.indexOf(u8, tables, "Count") == null);
    // 102 signals, one entry each (comma-newline count), plus 9 types.
    try std.testing.expectEqual(@as(usize, 111), std.mem.count(u8, tables, ",\n"));
    // as-const tables + literal-union types.
    try std.testing.expect(std.mem.indexOf(u8, tables, "} as const;") != null);
    try std.testing.expect(std.mem.indexOf(u8, tables, "export type FeatureID = (typeof FeatureID)[keyof typeof FeatureID];") != null);
}

test "buildConfig carries version and ingress URL" {
    const alloc = std.testing.allocator;
    const config = try browser_package.buildConfig(alloc, "0.2.0", "https://ingress.example.com");
    defer alloc.free(config);

    try std.testing.expect(std.mem.indexOf(u8, config, "SDK_VERSION = \"0.2.0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, config, "DEFAULT_INGRESS_URL = \"https://ingress.example.com\"") != null);
}
