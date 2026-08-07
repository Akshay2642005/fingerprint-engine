const std = @import("std");
const browser_package = @import("browser_package");

test "packageVersion parses the version field" {
    const alloc = std.testing.allocator;
    const version = try browser_package.packageVersion(alloc, "{\"name\":\"x\",\"version\":\"0.1.2\"}");
    defer alloc.free(version);
    try std.testing.expectEqualStrings("0.1.2", version);
}

test "featureIdTable covers every signal and skips the Count sentinel" {
    const alloc = std.testing.allocator;
    const table = try browser_package.featureIdTable(alloc);
    defer alloc.free(table);

    // First, last, and a middle signal.
    try std.testing.expect(std.mem.indexOf(u8, table, "UserAgent: 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, table, "IndexedDB: 49") != null);
    try std.testing.expect(std.mem.indexOf(u8, table, "CollectionTimestamp: 101") != null);
    // The internal sentinel must never leak into the JS surface.
    try std.testing.expect(std.mem.indexOf(u8, table, "Count") == null);
    // 102 signals, one entry each.
    try std.testing.expectEqual(@as(usize, 102), std.mem.count(u8, table, ",\n"));
}

test "featureTypeTable covers all value types" {
    const alloc = std.testing.allocator;
    const table = try browser_package.featureTypeTable(alloc);
    defer alloc.free(table);

    try std.testing.expect(std.mem.indexOf(u8, table, "Boolean: 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, table, "BytesArray: 8") != null);
    try std.testing.expectEqual(@as(usize, 9), std.mem.count(u8, table, ",\n"));
}

test "buildUmd substitutes all markers" {
    const alloc = std.testing.allocator;
    const template =
        "const WASM_BASE64 = \"__WASM_BASE64__\";\n" ++
        "const VERSION = \"__VERSION__\";\n" ++
        "const FeatureID = {\n" ++
        "\t/*__FEATURE_ID_TABLE__*/\n" ++
        "};\n" ++
        "const FeatureType = {\n" ++
        "\t/*__FEATURE_TYPE_TABLE__*/\n" ++
        "};\n";
    const umd = try browser_package.buildUmd(alloc, template, "QUJD", "0.1.2");
    defer alloc.free(umd);

    // No marker may survive substitution.
    try std.testing.expect(std.mem.indexOf(u8, umd, "__WASM_BASE64__") == null);
    try std.testing.expect(std.mem.indexOf(u8, umd, "__VERSION__") == null);
    try std.testing.expect(std.mem.indexOf(u8, umd, "/*__FEATURE") == null);
    // Base64 of "ABC", the version, and both generated tables appear.
    try std.testing.expect(std.mem.indexOf(u8, umd, "QUJD") != null);
    try std.testing.expect(std.mem.indexOf(u8, umd, "0.1.2") != null);
    try std.testing.expect(std.mem.indexOf(u8, umd, "UserAgent: 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, umd, "BytesArray: 8") != null);
}

test "buildEsm extracts the factory body and re-exports" {
    const alloc = std.testing.allocator;
    const template =
        \\const WASM_BASE64 = "__WASM_BASE64__";
        \\const VERSION = "__VERSION__";
        \\// Inlined WASM binary (base64)
        \\function collect() { return 42; }
        \\const sdk = { collect: collect };
        \\return sdk;
        \\
    ;
    const umd = try browser_package.buildUmd(alloc, template, "QUJD", "0.1.2");
    defer alloc.free(umd);

    const esm = try browser_package.buildEsm(alloc, umd, "0.1.2");
    defer alloc.free(esm);

    try std.testing.expect(std.mem.indexOf(u8, esm, "function fingerprintSdk() {") != null);
    try std.testing.expect(std.mem.indexOf(u8, esm, "export default collect;") != null);
    try std.testing.expect(std.mem.indexOf(u8, esm, "export { collect as getFingerprint };") != null);
}

test "buildDts declares the full FeatureID surface" {
    const alloc = std.testing.allocator;
    const dts = try browser_package.buildDts(alloc, "0.1.2");
    defer alloc.free(dts);

    try std.testing.expect(std.mem.indexOf(u8, dts, "readonly UserAgent: 0;") != null);
    try std.testing.expect(std.mem.indexOf(u8, dts, "readonly CollectionTimestamp: 101;") != null);
    // Count must not appear in the public types.
    try std.testing.expect(std.mem.indexOf(u8, dts, "Count") == null);
    try std.testing.expect(std.mem.indexOf(u8, dts, "export default collect;") != null);
}
