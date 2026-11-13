//! Compose surface tests (ADR-014 §4).
//!
//! The metrics/probe endpoints are unauthenticated by design, so they must
//! stay network-internal: `compose.yml` declares them with `expose:` and only
//! the local-development overlay publishes them — on loopback. This guards the
//! regression that briefly published `9090`/`9091` on every host interface.
//!
//! The checks walk the YAML by section instead of substring-matching the whole
//! file, so a comment that mentions an old mapping cannot pass the test and a
//! publish in any accepted form (`0.0.0.0:9090:9090`, the long
//! `target:`/`published:` form) cannot slip through.

const std = @import("std");
const testing = std.testing;

fn readFile(alloc: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.fs.cwd().readFileAlloc(alloc, path, 64 * 1024);
}

/// The compose sections that can carry a container port.
const Section = enum { other, ports, expose };

/// True when `port` appears as a whole number in one of the `- ...` entries
/// belonging to `section`.
fn listsPort(contents: []const u8, section: Section, port: []const u8) bool {
    var current: Section = .other;
    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        if (line[0] == '-') {
            if (current == section and containsPort(line, port)) return true;
            continue;
        }
        current = if (std.mem.startsWith(u8, line, "ports:"))
            .ports
        else if (std.mem.startsWith(u8, line, "expose:"))
            .expose
        else
            .other;
    }
    return false;
}

/// Whole-number match: `9090` must not match `90901`.
fn containsPort(entry: []const u8, port: []const u8) bool {
    var from: usize = 0;
    while (std.mem.indexOfPos(u8, entry, from, port)) |idx| {
        const before_ok = idx == 0 or !std.ascii.isDigit(entry[idx - 1]);
        const end = idx + port.len;
        const after_ok = end >= entry.len or !std.ascii.isDigit(entry[end]);
        if (before_ok and after_ok) return true;
        from = idx + 1;
    }
    return false;
}

/// Every published entry must be bound to loopback, so a local overlay can
/// never accidentally re-expose the surface to the network.
fn publishAllOnLoopback(contents: []const u8) bool {
    var in_ports = false;
    var saw_entry = false;
    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        if (line[0] != '-') {
            in_ports = std.mem.startsWith(u8, line, "ports:");
            continue;
        }
        if (!in_ports) continue;
        saw_entry = true;
        if (!std.mem.startsWith(u8, line, "- \"127.0.0.1:")) return false;
    }
    return saw_entry;
}

test "compose: operational ports are exposed, never published" {
    const alloc = testing.allocator;
    const contents = try readFile(alloc, "compose.yml");
    defer alloc.free(contents);

    for ([_][]const u8{ "9090", "9091" }) |port| {
        try testing.expect(!listsPort(contents, .ports, port));
        try testing.expect(listsPort(contents, .expose, port));
    }
}

test "compose: the local override publishes the operational ports on loopback" {
    const alloc = testing.allocator;
    const contents = try readFile(alloc, "compose.override.yml");
    defer alloc.free(contents);

    for ([_][]const u8{ "9090", "9091" }) |port| {
        try testing.expect(listsPort(contents, .ports, port));
        try testing.expect(!listsPort(contents, .expose, port));
    }
    try testing.expect(publishAllOnLoopback(contents));
}
