//! Dist surface guard for the browser SDK (DESIGN §9.4.6).
//!
//! Walks the generated `dist/` tree and fails the `clients:browser` step if
//! forbidden surface leaks into the shipped package:
//!   - `.wasm` modules (the browser never runs the engine),
//!   - wasm-instantiation markers in any JS file (base64 blobs, the
//!     `WebAssembly` API, the old engine exports),
//!   - `hash` / `compute` identifiers in the public `.d.ts` surface — the
//!     canonical digest is computed server-side by the workers, never by the
//!     browser SDK.
//!
//! The check is intentionally conservative: doc comments legitimately
//! mention the server-side hashing pipeline, so declarations are stripped of
//! comments before identifier matching, and only word-boundary matches count
//! (`CanvasHash` is a feature id, not a hash export).
const std = @import("std");

/// Markers of a wasm-inlined or engine-backed bundle. If any of these
/// appears in a shipped JS file, the package regressed to the old surface.
const wasm_markers = [_][]const u8{
    "WASM_BASE64",
    "WebAssembly",
    "atob(",
    "fingerprint_compute",
    "fingerprint_hash",
    "fingerprint_init",
    "fingerprint_get_scratch_ptr",
};

/// Identifiers banned from the public type surface.
const banned_identifiers = [_][]const u8{ "hash", "compute" };

pub const DistFile = struct {
    path: []const u8,
    contents: []const u8,
};

pub const Violation = struct {
    path: []const u8,
    detail: []const u8,
};

/// Scans a set of dist files and returns the violations found (empty when
/// clean). `detail` is either a static string or a marker borrowed from
/// `wasm_markers`; both outlive the call.
pub fn scan(alloc: std.mem.Allocator, files: []const DistFile) ![]Violation {
    var violations = std.ArrayList(Violation).init(alloc);
    for (files) |file| {
        if (std.mem.endsWith(u8, file.path, ".wasm")) {
            try violations.append(.{
                .path = file.path,
                .detail = "wasm module shipped in the browser package",
            });
            continue;
        }
        const is_js = std.mem.endsWith(u8, file.path, ".js");
        const is_dts = std.mem.endsWith(u8, file.path, ".d.ts");
        if (!is_js and !is_dts) continue;

        if (is_js) {
            for (wasm_markers) |marker| {
                if (std.mem.indexOf(u8, file.contents, marker) != null) {
                    try violations.append(.{ .path = file.path, .detail = marker });
                }
            }
            continue;
        }

        // Public type surface: strip comments (JSDoc legitimately describes
        // the server-side pipeline), then match banned identifiers at word
        // boundaries.
        const code = try stripComments(alloc, file.contents);
        defer alloc.free(code);
        for (banned_identifiers) |name| {
            if (containsIdentifier(code, name)) {
                try violations.append(.{ .path = file.path, .detail = name });
            }
        }
    }
    return violations.toOwnedSlice();
}

/// Removes `/* ... */` and `// ...` comment spans, replacing them with
/// nothing (identifiers never span comments, so concatenation is safe).
fn stripComments(alloc: std.mem.Allocator, contents: []const u8) ![]u8 {
    var out = std.ArrayList(u8).init(alloc);
    const writer = out.writer();
    var i: usize = 0;
    while (i < contents.len) {
        if (std.mem.startsWith(u8, contents[i..], "/*")) {
            const rest = contents[i + 2 ..];
            const end = std.mem.indexOf(u8, rest, "*/") orelse rest.len;
            i += 2 + end + 2;
        } else if (std.mem.startsWith(u8, contents[i..], "//")) {
            const nl = std.mem.indexOfScalar(u8, contents[i..], '\n') orelse contents.len;
            i += nl;
        } else {
            try writer.writeByte(contents[i]);
            i += 1;
        }
    }
    return out.toOwnedSlice();
}

/// Matches `needle` at word boundaries only, so `CanvasHash` never flags the
/// `hash` check while a top-level `hash` export would.
fn containsIdentifier(haystack: []const u8, needle: []const u8) bool {
    var i: usize = 0;
    while (std.mem.indexOfPos(u8, haystack, i, needle)) |pos| {
        const before_ok = pos == 0 or !isIdentChar(haystack[pos - 1]);
        const after = pos + needle.len;
        const after_ok = after >= haystack.len or !isIdentChar(haystack[after]);
        if (before_ok and after_ok) return true;
        i = pos + 1;
    }
    return false;
}

fn isIdentChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

pub fn main() !void {
    var arena_instance = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_instance.deinit();
    const alloc = arena_instance.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);
    if (args.len != 2) {
        std.debug.print("usage: dist_surface <dist-dir>\n", .{});
        std.process.exit(2);
    }

    var files = std.ArrayList(DistFile).init(alloc);
    var dir = try std.fs.cwd().openDir(args[1], .{
        .access_sub_paths = true,
        .iterate = true,
    });
    defer dir.close();
    var walker = try dir.walk(alloc);
    defer walker.deinit();
    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;
        const contents = try entry.dir.readFileAlloc(alloc, entry.basename, 4 << 20);
        try files.append(.{
            .path = try alloc.dupe(u8, entry.path),
            .contents = contents,
        });
    }

    const violations = try scan(alloc, files.items);
    if (violations.len > 0) {
        const stderr = std.io.getStdErr().writer();
        for (violations) |violation| {
            try stderr.print("dist surface violation: {s}: {s}\n", .{ violation.path, violation.detail });
        }
        std.process.exit(1);
    }
    try std.io.getStdOut().writer().print("dist surface: OK ({d} files)\n", .{files.items.len});
}
