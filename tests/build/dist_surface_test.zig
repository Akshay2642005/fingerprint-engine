const std = @import("std");
const dist_surface = @import("dist_surface");

fn scanStrings(alloc: std.mem.Allocator, files: []const struct { []const u8, []const u8 }) ![]dist_surface.Violation {
    var dist_files = std.ArrayList(dist_surface.DistFile).init(alloc);
    defer dist_files.deinit();
    for (files) |file| {
        try dist_files.append(.{ .path = file[0], .contents = file[1] });
    }
    return dist_surface.scan(alloc, dist_files.items);
}

test "dist surface: clean package passes" {
    const alloc = std.testing.allocator;
    const files = [_]struct { []const u8, []const u8 }{
        .{ "index.js", "export function collect() {}" },
        .{ "package.js", "export const MAGIC = \"FNGR\";" },
        .{ "index.d.ts", "export declare function collect(options?: CollectOptions): Promise<CollectResult>;" },
    };
    const violations = try scanStrings(alloc, &files);
    defer alloc.free(violations);
    try std.testing.expectEqual(@as(usize, 0), violations.len);
}

test "dist surface: wasm file is rejected" {
    const alloc = std.testing.allocator;
    const files = [_]struct { []const u8, []const u8 }{
        .{ "engine.wasm", "AGFzbQ" },
    };
    const violations = try scanStrings(alloc, &files);
    defer alloc.free(violations);
    try std.testing.expectEqual(@as(usize, 1), violations.len);
    try std.testing.expect(std.mem.indexOf(u8, violations[0].detail, "wasm") != null);
}

test "dist surface: wasm-instantiation markers are rejected in js" {
    const alloc = std.testing.allocator;
    const files = [_]struct { []const u8, []const u8 }{
        .{ "index.js", "const WASM_BASE64 = \"AGFzbQ\"; WebAssembly.instantiate(bytes); fingerprint_compute();" },
    };
    const violations = try scanStrings(alloc, &files);
    defer alloc.free(violations);
    // Three distinct markers on one file.
    try std.testing.expectEqual(@as(usize, 3), violations.len);
}

test "dist surface: hash/compute identifiers are rejected in d.ts" {
    const alloc = std.testing.allocator;
    const files = [_]struct { []const u8, []const u8 }{
        .{ "index.d.ts", "export declare function hash(package: Uint8Array): string;\nexport declare function compute(): void;" },
    };
    const violations = try scanStrings(alloc, &files);
    defer alloc.free(violations);
    try std.testing.expectEqual(@as(usize, 2), violations.len);
}

test "dist surface: comments and composite ids never flag" {
    const alloc = std.testing.allocator;
    const files = [_]struct { []const u8, []const u8 }{
        // JSDoc mentions the server-side pipeline; feature ids embed "hash".
        .{ "index.d.ts", "/** Workers hash the package server-side. */\nexport declare function collect(): void;\nexport declare const FeatureID: { CanvasHash: 35; AudioHash: 43; };" },
    };
    const violations = try scanStrings(alloc, &files);
    defer alloc.free(violations);
    try std.testing.expectEqual(@as(usize, 0), violations.len);
}
