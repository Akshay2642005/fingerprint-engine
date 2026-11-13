//! Compose surface tests (ADR-014 §4).
//!
//! The metrics/probe endpoints are unauthenticated by design, so they must
//! stay network-internal: `compose.yml` declares them with `expose:` and only
//! the local-development overlay publishes them — on loopback. This guards the
//! regression that briefly published `9090`/`9091` on every host interface.

const std = @import("std");
const testing = std.testing;

fn readFile(alloc: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.fs.cwd().readFileAlloc(alloc, path, 64 * 1024);
}

test "compose: operational ports are exposed, never published" {
    const alloc = testing.allocator;
    const contents = try readFile(alloc, "compose.yml");
    defer alloc.free(contents);

    // A `host:container` mapping is a publish; the plain container port inside
    // `expose:` is the only allowed form.
    try testing.expect(std.mem.indexOf(u8, contents, "9090:9090") == null);
    try testing.expect(std.mem.indexOf(u8, contents, "9091:9091") == null);
    try testing.expect(std.mem.indexOf(u8, contents, "\"9090\"") != null);
    try testing.expect(std.mem.indexOf(u8, contents, "\"9091\"") != null);
}

test "compose: the local override publishes the operational ports on loopback" {
    const alloc = testing.allocator;
    const contents = try readFile(alloc, "compose.override.yml");
    defer alloc.free(contents);

    try testing.expect(std.mem.indexOf(u8, contents, "127.0.0.1:9090:9090") != null);
    try testing.expect(std.mem.indexOf(u8, contents, "127.0.0.1:9091:9091") != null);
}
