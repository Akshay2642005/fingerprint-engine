comptime {
    _ = @import("adapter/loopback_test.zig");
    _ = @import("adapter/tcp_test.zig");
    _ = @import("adapter/transport_test.zig");
    _ = @import("browser/bindings_test.zig");
    _ = @import("browser/wasm_test.zig");
    _ = @import("build/browser_package_test.zig");
    _ = @import("core/bounds_test.zig");
    _ = @import("core/entropy_test.zig");
    _ = @import("core/feature_sim_test.zig");
    _ = @import("core/feature_test.zig");
    _ = @import("core/fingerprint_sim_test.zig");
    _ = @import("core/hasher_test.zig");
    _ = @import("core/hashing_fingerprint_test.zig");
    _ = @import("core/normalize_test.zig");
    _ = @import("core/required_test.zig");
    _ = @import("core/risk_test.zig");
    _ = @import("core/types_test.zig");
    _ = @import("data/fingerprints/fingerprints_test.zig");
    _ = @import("engine/determinism_test.zig");
    _ = @import("engine/dispatch_test.zig");
    _ = @import("engine/integration_test.zig");
    _ = @import("engine/replay_test.zig");
    _ = @import("engine/roundtrip_test.zig");
    _ = @import("engine/unknown_version_test.zig");
    _ = @import("fuzz/fuzz_decode.zig");
    _ = @import("fuzz/fuzz_hashing.zig");
    _ = @import("fuzz/fuzz_normalize.zig");
    _ = @import("io/channel_test.zig");
    _ = @import("io/completion_test.zig");
    _ = @import("io/dispatcher_test.zig");
    _ = @import("io/executor_test.zig");
    _ = @import("io/frame_test.zig");
    _ = @import("io/message_test.zig");
    _ = @import("io/reader_writer_test.zig");
    _ = @import("io/ring_buffer_test.zig");
    _ = @import("model/api_test.zig");
    _ = @import("model/definitions_test.zig");
    _ = @import("model/feature_binding_test.zig");
    _ = @import("model/fingerprint_test.zig");
    _ = @import("model/integration_test.zig");
    _ = @import("model/metadata_test.zig");
    _ = @import("model/model_test.zig");
    _ = @import("model/registry_test.zig");
    _ = @import("model/value_test.zig");
    _ = @import("serialization/binary_test.zig");
    _ = @import("serialization/codec_test.zig");
    _ = @import("serialization/integrity_test.zig");
    _ = @import("serialization/json_test.zig");
    _ = @import("utils_test.zig");
}

const quine =
    \\const std = @import("std");
    \\const builtin = @import("builtin");
    \\const assert = std.debug.assert;
    \\
    \\const MiB = 1024 * 1024;
    \\
    \\// This file is the test registry: the comptime block above imports every
    \\// test file under tests/ except this file itself and the test_utils module
    \\// (wired in as a named module from build.zig). It includes a self-check
    \\// that keeps the import list
    \\// fresh: after adding or removing a test file, `zig build test` fails with
    \\// "tests/root.zig needs updating."; rerun with SNAP_UPDATE=1 to regenerate.
    \\test "registry: import list is up to date" {
    \\    var arena_instance = std.heap.ArenaAllocator.init(std.testing.allocator);
    \\    defer arena_instance.deinit();
    \\    const arena = arena_instance.allocator();
    \\
    \\    // The run step is pinned to the repository root (see build.zig), so the
    \\    // walk and the self-read below agree on paths.
    \\    var tests_dir = try std.fs.cwd().openDir("tests", .{
    \\        .access_sub_paths = true,
    \\        .iterate = true,
    \\    });
    \\
    \\    var generated = std.ArrayList(u8).init(arena);
    \\    const writer = generated.writer();
    \\
    \\    // Reproduce the comptime block above from the files on disk...
    \\    try writer.writeAll("comptime {\n");
    \\    for (try test_files(arena, tests_dir)) |path| {
    \\        try writer.print("    _ = @import(\"{s}\");\n", .{path});
    \\    }
    \\    try writer.writeAll("}\n\n");
    \\
    \\    // ...then the `quine` declaration (the rest of this file quoted), then
    \\    // the real code. The result must equal the file on disk exactly.
    \\    try writer.writeAll("const quine =\n");
    \\    var quine_lines = std.mem.splitScalar(u8, quine, '\n');
    \\    while (quine_lines.next()) |line| {
    \\        try writer.print("    \\\\{s}\n", .{line});
    \\    }
    \\    try writer.writeAll(";\n\n");
    \\    try writer.writeAll(quine);
    \\
    \\    const root_on_disk = try tests_dir.readFileAlloc(arena, "root.zig", 1 * MiB);
    \\    if (!std.mem.eql(u8, root_on_disk, generated.items)) {
    \\        if (std.process.hasEnvVarConstant("SNAP_UPDATE")) {
    \\            try tests_dir.writeFile(.{
    \\                .sub_path = "root.zig",
    \\                .data = generated.items,
    \\                .flags = .{ .exclusive = false, .truncate = true },
    \\            });
    \\        } else {
    \\            std.debug.print("tests/root.zig needs updating.\n", .{});
    \\            std.debug.print(
    \\                "Rerun with SNAP_UPDATE=1 environmental variable to update the contents.\n",
    \\                .{},
    \\            );
    \\            assert(false);
    \\        }
    \\    }
    \\}
    \\
    \\fn test_files(arena: std.mem.Allocator, tests_dir: std.fs.Dir) ![]const []const u8 {
    \\    // Different platforms can walk the directory in different orders.
    \\    // Store the paths and sort them to ensure consistency.
    \\    var result = std.ArrayList([]const u8).init(arena);
    \\
    \\    var walker = try tests_dir.walk(arena);
    \\    defer walker.deinit();
    \\
    \\    while (try walker.next()) |entry| {
    \\        if (entry.kind != .file) continue;
    \\
    \\        const entry_path = try arena.dupe(u8, entry.path);
    \\
    \\        // Replace the path separator to be Unix-style, for consistency on
    \\        // Windows.
    \\        if (builtin.os.tag == .windows) {
    \\            std.mem.replaceScalar(u8, entry_path, '\\', '/');
    \\        }
    \\
    \\        if (!std.mem.endsWith(u8, entry_path, ".zig")) continue;
    \\
    \\        // The registry itself and the test_utils module (imported as a named
    \\        // module from build.zig) are excluded from discovery.
    \\        if (std.mem.eql(u8, entry_path, "root.zig")) continue;
    \\        if (std.mem.startsWith(u8, entry_path, "utils/")) continue;
    \\
    \\        const contents = try tests_dir.readFileAlloc(arena, entry_path, 1 * MiB);
    \\        var line_iterator = std.mem.splitScalar(u8, contents, '\n');
    \\        while (line_iterator.next()) |line| {
    \\            const line_trimmed = std.mem.trimLeft(u8, line, " ");
    \\            if (std.mem.startsWith(u8, line_trimmed, "test ")) {
    \\                try result.append(entry_path);
    \\                break;
    \\            }
    \\        }
    \\    }
    \\
    \\    std.mem.sort(
    \\        []const u8,
    \\        result.items,
    \\        {},
    \\        struct {
    \\            fn less_than_fn(_: void, a: []const u8, b: []const u8) bool {
    \\                return std.mem.order(u8, a, b) == .lt;
    \\            }
    \\        }.less_than_fn,
    \\    );
    \\
    \\    return result.items;
    \\}
    \\
;

const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;

const MiB = 1024 * 1024;

// This file is the test registry: the comptime block above imports every
// test file under tests/ except this file itself and the test_utils module
// (wired in as a named module from build.zig). It includes a self-check
// that keeps the import list
// fresh: after adding or removing a test file, `zig build test` fails with
// "tests/root.zig needs updating."; rerun with SNAP_UPDATE=1 to regenerate.
test "registry: import list is up to date" {
    var arena_instance = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    // The run step is pinned to the repository root (see build.zig), so the
    // walk and the self-read below agree on paths.
    var tests_dir = try std.fs.cwd().openDir("tests", .{
        .access_sub_paths = true,
        .iterate = true,
    });

    var generated = std.ArrayList(u8).init(arena);
    const writer = generated.writer();

    // Reproduce the comptime block above from the files on disk...
    try writer.writeAll("comptime {\n");
    for (try test_files(arena, tests_dir)) |path| {
        try writer.print("    _ = @import(\"{s}\");\n", .{path});
    }
    try writer.writeAll("}\n\n");

    // ...then the `quine` declaration (the rest of this file quoted), then
    // the real code. The result must equal the file on disk exactly.
    try writer.writeAll("const quine =\n");
    var quine_lines = std.mem.splitScalar(u8, quine, '\n');
    while (quine_lines.next()) |line| {
        try writer.print("    \\\\{s}\n", .{line});
    }
    try writer.writeAll(";\n\n");
    try writer.writeAll(quine);

    const root_on_disk = try tests_dir.readFileAlloc(arena, "root.zig", 1 * MiB);
    if (!std.mem.eql(u8, root_on_disk, generated.items)) {
        if (std.process.hasEnvVarConstant("SNAP_UPDATE")) {
            try tests_dir.writeFile(.{
                .sub_path = "root.zig",
                .data = generated.items,
                .flags = .{ .exclusive = false, .truncate = true },
            });
        } else {
            std.debug.print("tests/root.zig needs updating.\n", .{});
            std.debug.print(
                "Rerun with SNAP_UPDATE=1 environmental variable to update the contents.\n",
                .{},
            );
            assert(false);
        }
    }
}

fn test_files(arena: std.mem.Allocator, tests_dir: std.fs.Dir) ![]const []const u8 {
    // Different platforms can walk the directory in different orders.
    // Store the paths and sort them to ensure consistency.
    var result = std.ArrayList([]const u8).init(arena);

    var walker = try tests_dir.walk(arena);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;

        const entry_path = try arena.dupe(u8, entry.path);

        // Replace the path separator to be Unix-style, for consistency on
        // Windows.
        if (builtin.os.tag == .windows) {
            std.mem.replaceScalar(u8, entry_path, '\\', '/');
        }

        if (!std.mem.endsWith(u8, entry_path, ".zig")) continue;

        // The registry itself and the test_utils module (imported as a named
        // module from build.zig) are excluded from discovery.
        if (std.mem.eql(u8, entry_path, "root.zig")) continue;
        if (std.mem.startsWith(u8, entry_path, "utils/")) continue;

        const contents = try tests_dir.readFileAlloc(arena, entry_path, 1 * MiB);
        var line_iterator = std.mem.splitScalar(u8, contents, '\n');
        while (line_iterator.next()) |line| {
            const line_trimmed = std.mem.trimLeft(u8, line, " ");
            if (std.mem.startsWith(u8, line_trimmed, "test ")) {
                try result.append(entry_path);
                break;
            }
        }
    }

    std.mem.sort(
        []const u8,
        result.items,
        {},
        struct {
            fn less_than_fn(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.order(u8, a, b) == .lt;
            }
        }.less_than_fn,
    );

    return result.items;
}
