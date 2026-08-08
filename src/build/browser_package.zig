//! Build-time generator for the browser SDK npm package.
//!
//! Produces dist/fingerprint.umd.js, dist/fingerprint.esm.js, and
//! dist/index.d.ts inside the browser client package
//! (src/clients/browser/) from:
//!   - the compiled WASM binary (base64-inlined into the UMD bundle),
//!   - scripts/fingerprint-umd-template.js (UMD factory body),
//!   - package.json (version),
//!   - model.FeatureID / model.FeatureType (single source of truth for the
//!     JS constant tables — replaces the previously duplicated hardcoded maps).
//!
//! Replaces the former Node.js build script (build.mjs) so the npm package is
//! produced entirely by `zig build clients:browser`. The run step has no
//! captured outputs, so the build runner treats it as side-effecting and
//! executes it on every invocation (it rewrites dist/ in the source tree).
//!
//! The npm payload is strictly the runtime SDK — no demo pages, no examples.
//! The browser demo lives outside the package at examples/demo.html and is
//! served from the repo checkout for development only.
const std = @import("std");
const model = @import("model");

const usage =
    \\usage: browser_package <wasm> <template> <package.json> <out-dir>
    \\
;

const Substitution = struct {
    marker: []const u8,
    replacement: []const u8,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);
    if (args.len != 5) {
        std.debug.print("{s}", .{usage});
        std.process.exit(1);
    }

    const wasm_path = args[1];
    const template_path = args[2];
    const package_json_path = args[3];
    const out_dir = args[4];

    // 1. Base64-encode the WASM binary (inlined into the UMD bundle).
    const wasm_bytes = try std.fs.cwd().readFileAlloc(alloc, wasm_path, 4 << 20);
    defer alloc.free(wasm_bytes);
    const wasm_b64_len = std.base64.standard.Encoder.calcSize(wasm_bytes.len);
    const wasm_base64 = try alloc.alloc(u8, wasm_b64_len);
    defer alloc.free(wasm_base64);
    _ = std.base64.standard.Encoder.encode(wasm_base64, wasm_bytes);

    // 2. Read the package version.
    const pkg_json = try std.fs.cwd().readFileAlloc(alloc, package_json_path, 1 << 16);
    defer alloc.free(pkg_json);
    const version = try packageVersion(alloc, pkg_json);
    defer alloc.free(version);

    // 3. Read the UMD template.
    const template = try std.fs.cwd().readFileAlloc(alloc, template_path, 1 << 20);
    defer alloc.free(template);

    // 4. Substitute into the UMD bundle.
    const umd = try buildUmd(alloc, template, wasm_base64, version);
    defer alloc.free(umd);

    // 5. Derive the ESM bundle from the UMD factory body.
    const esm = try buildEsm(alloc, umd, version);
    defer alloc.free(esm);

    // 6. Generate the type declarations.
    const dts = try buildDts(alloc, version);
    defer alloc.free(dts);

    // 7. Write dist/.
    const dist_path = try std.fs.path.join(alloc, &.{ out_dir, "dist" });
    defer alloc.free(dist_path);
    try std.fs.cwd().makePath(dist_path);
    try writeFile(alloc, dist_path, "fingerprint.umd.js", umd);
    try writeFile(alloc, dist_path, "fingerprint.esm.js", esm);
    try writeFile(alloc, dist_path, "index.d.ts", dts);

    std.debug.print(
        "browser package: dist/fingerprint.umd.js ({d} KB), fingerprint.esm.js ({d} KB), index.d.ts ({d} KB)\n",
        .{
            umd.len / 1024,
            esm.len / 1024,
            dts.len / 1024,
        },
    );
}

/// Version string read from a package.json document.
pub fn packageVersion(alloc: std.mem.Allocator, json: []const u8) ![]const u8 {
    var parsed = try std.json.parseFromSlice(std.json.Value, alloc, json, .{});
    defer parsed.deinit();
    const version = parsed.value.object.get("version") orelse return error.MissingVersion;
    return try alloc.dupe(u8, version.string);
}

/// JS object-literal body for the FeatureID constants (e.g. `UserAgent: 0,`).
/// Skips the internal `Count` sentinel. Names and values come straight from
/// model.FeatureID, keeping the JS package in lock-step with the engine.
pub fn featureIdTable(alloc: std.mem.Allocator) ![]const u8 {
    var out = std.ArrayList(u8).init(alloc);
    errdefer out.deinit();
    const writer = out.writer();
    const fields = @typeInfo(model.FeatureID).@"enum".fields;
    inline for (fields) |field| {
        if (comptime std.mem.eql(u8, field.name, "Count")) continue;
        try writer.print("\t\t\t{s}: {d},\n", .{ field.name, field.value });
    }
    return out.toOwnedSlice();
}

/// JS object-literal body for the FeatureType constants.
pub fn featureTypeTable(alloc: std.mem.Allocator) ![]const u8 {
    var out = std.ArrayList(u8).init(alloc);
    errdefer out.deinit();
    const writer = out.writer();
    const fields = @typeInfo(model.FeatureType).@"enum".fields;
    inline for (fields) |field| {
        try writer.print("\t\t\t{s}: {d},\n", .{ field.name, field.value });
    }
    return out.toOwnedSlice();
}

/// UMD bundle: template with the wasm base64, version, and constant tables
/// substituted for their markers.
pub fn buildUmd(
    alloc: std.mem.Allocator,
    template: []const u8,
    wasm_base64: []const u8,
    version: []const u8,
) ![]const u8 {
    const fid_table = try featureIdTable(alloc);
    defer alloc.free(fid_table);
    const ftype_table = try featureTypeTable(alloc);
    defer alloc.free(ftype_table);

    const substitutions = [_]Substitution{
        .{ .marker = "__WASM_BASE64__", .replacement = wasm_base64 },
        .{ .marker = "__VERSION__", .replacement = version },
        .{ .marker = "/*__FEATURE_ID_TABLE__*/", .replacement = fid_table },
        .{ .marker = "/*__FEATURE_TYPE_TABLE__*/", .replacement = ftype_table },
    };

    var out = std.ArrayList(u8).init(alloc);
    errdefer out.deinit();
    const writer = out.writer();

    var rest = template;
    while (true) {
        var best_idx: usize = std.math.maxInt(usize);
        var best_sub: ?*const Substitution = null;
        for (&substitutions) |*sub| {
            if (std.mem.indexOf(u8, rest, sub.marker)) |idx| {
                if (idx < best_idx) {
                    best_idx = idx;
                    best_sub = sub;
                }
            }
        }
        const sub = best_sub orelse {
            try writer.writeAll(rest);
            break;
        };
        try writer.writeAll(rest[0..best_idx]);
        try writer.writeAll(sub.replacement);
        rest = rest[best_idx + sub.marker.len ..];
    }
    return out.toOwnedSlice();
}

/// ESM bundle: the UMD factory body re-exported as a module. Mirrors the
/// previous build.mjs extraction (marker comment through the final
/// `return sdk;`) so the module surface is unchanged.
pub fn buildEsm(alloc: std.mem.Allocator, umd: []const u8, version: []const u8) ![]const u8 {
    const marker_line = "// Inlined WASM binary (base64)";
    const return_sdk = "return sdk;";
    const factory_start = std.mem.indexOf(u8, umd, marker_line) orelse
        return error.TemplateMarkerNotFound;
    const factory_end = std.mem.lastIndexOf(u8, umd, return_sdk) orelse
        return error.TemplateReturnNotFound;
    const factory_body = umd[factory_start .. factory_end + return_sdk.len];

    var out = std.ArrayList(u8).init(alloc);
    errdefer out.deinit();
    const writer = out.writer();
    try writer.print(
        "/**\n * @fingerprint/sdk v{s} (ES Module)\n */\nfunction fingerprintSdk() {{\n",
        .{version},
    );
    try writer.writeAll(std.mem.trim(u8, factory_body, " \t\r\n"));
    try writer.writeAll("\n}\n\n");
    try writer.writeAll(
        "const { collect, reset, FeatureID, FeatureType, ErrorCode, getFeatureIDs } = " ++
            "fingerprintSdk();\n\n" ++
            "export { collect, reset, FeatureID, FeatureType, ErrorCode, getFeatureIDs };\n" ++
            "export { collect as getFingerprint };\n" ++
            "export default collect;\n",
    );
    return out.toOwnedSlice();
}

/// TypeScript declarations for the package. FeatureID/FeatureType entries are
/// generated from the model enums.
pub fn buildDts(alloc: std.mem.Allocator, version: []const u8) ![]const u8 {
    var out = std.ArrayList(u8).init(alloc);
    errdefer out.deinit();
    const writer = out.writer();
    try writer.print("/**\n * @fingerprint/sdk v{s} — TypeScript declarations\n */\n\n", .{version});
    try writer.writeAll(
        \\export interface CollectResult {
        \\  hex: string;
        \\  digest: Uint8Array;
        \\  risk: number;
        \\  entropy: number;
        \\  warnings: number;
        \\  signals: number;
        \\  collectedAt: number;
        \\}
        \\
        \\export declare const FeatureID: {
        \\
    );
    const fid_fields = @typeInfo(model.FeatureID).@"enum".fields;
    inline for (fid_fields) |field| {
        if (comptime std.mem.eql(u8, field.name, "Count")) continue;
        try writer.print("  readonly {s}: {d};\n", .{ field.name, field.value });
    }
    try writer.writeAll("};");
    try writer.writeAll("\n\nexport declare const FeatureType: {\n");
    const ftype_fields = @typeInfo(model.FeatureType).@"enum".fields;
    inline for (ftype_fields) |field| {
        try writer.print("  readonly {s}: {d};\n", .{ field.name, field.value });
    }
    try writer.writeAll(
        \\};
        \\
        \\export declare function collect(): Promise<CollectResult>;
        \\export declare function reset(): void;
        \\export declare function getFeatureIDs(): typeof FeatureID;
        \\export { collect as getFingerprint };
        \\export default collect;
        \\
    );
    return out.toOwnedSlice();
}

fn writeFile(
    alloc: std.mem.Allocator,
    dir_path: []const u8,
    name: []const u8,
    contents: []const u8,
) !void {
    const path = try std.fs.path.join(alloc, &.{ dir_path, name });
    defer alloc.free(path);
    try std.fs.cwd().writeFile(.{ .sub_path = path, .data = contents });
}
