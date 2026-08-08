//! Grab bag of automation scripts around Fingerprint Engine.
//!
//! Design rationale:
//! - Bash is not cross platform, suffers from high accidental complexity, and
//!   is a second language. We strive to centralize on Zig for all of the things.
//! - While build.zig is great for _building_ software using a graph of tasks
//!   with dependency tracking, higher-level orchestration is easier if you
//!   just write direct imperative code.
//! - To minimize the number of things that need compiling and improve link
//!   times, all scripts are subcommands of a single binary.
//!
//!   This is a special case of the following rule-of-thumb: length of
//!   `build.zig` should be O(1).
const std = @import("std");
const model = @import("model");
const serialization = @import("serialization");
const engine = @import("engine");

const usage =
    \\Usage:
    \\
    \\  zig build scripts -- [-h | --help]
    \\
    \\  zig build scripts -- help
    \\
    \\  zig build scripts -- generate fixture <name>
    \\    Write a canonical test fixture under tests/fixtures/ and print the
    \\    engine's hash of it — the digest the worker e2e tests pin as a
    \\    compile-time constant. Run from the repository root.
    \\
;

/// Fixture packages are defined here, in the same model code the engine
/// uses, so the bytes can never drift from what the worker actually hashes.
const fixtures = .{
    .signal_package_v2 = struct {
        const name = "signal-package-v2";
        const path = "tests/fixtures/fingerprints/signal-package-v2.bin";

        const package_id = [16]u8{
            0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
            0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10,
        };

        fn fingerprint() model.Fingerprint {
            return .{
                .metadata = .{
                    .schema_version = serialization.schema_version_v2,
                    .sdk_version = "0.2.0",
                    .collected_at = 1700000000123,
                    .package_id = package_id,
                },
                .features = &.{
                    model.Feature{ .id = model.FeatureID.UserAgent, .value = .{ .String = "Mozilla/5.0" } },
                    model.Feature{ .id = model.FeatureID.CookieEnabled, .value = .{ .Boolean = true } },
                    model.Feature{ .id = model.FeatureID.HardwareConcurrency, .value = .{ .Integer = 8 } },
                },
            };
        }
    },
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    const subcommand = if (args.len > 1) args[1] else "help";
    if (std.mem.eql(u8, subcommand, "help") or
        std.mem.eql(u8, subcommand, "-h") or
        std.mem.eql(u8, subcommand, "--help"))
    {
        try std.io.getStdOut().writer().writeAll(usage);
        return;
    }

    if (std.mem.eql(u8, subcommand, "generate")) {
        try generate(alloc, args);
        return;
    }

    std.debug.print("unknown subcommand '{s}'\n\n{s}", .{ subcommand, usage });
    std.process.exit(1);
}

fn generate(alloc: std.mem.Allocator, args: []const []const u8) !void {
    const name = if (args.len > 2) args[2] else "";
    if (!std.mem.eql(u8, name, "fixture") or args.len < 4) {
        std.debug.print("usage: zig build scripts -- generate fixture <name>\n", .{});
        std.process.exit(1);
    }
    const fixture_name = args[3];
    if (std.mem.eql(u8, fixture_name, fixtures.signal_package_v2.name)) {
        return generateSignalPackageV2(alloc);
    }
    std.debug.print("unknown fixture '{s}'\n\n{s}", .{ fixture_name, usage });
    std.process.exit(1);
}

/// Serializes the canonical v2 signal package, writes it under
/// tests/fixtures/, and prints its engine hash.
fn generateSignalPackageV2(alloc: std.mem.Allocator) !void {
    const F = fixtures.signal_package_v2;
    const fp = F.fingerprint();

    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try serialization.encode(fbs.writer(), fp);
    const bytes = fbs.getWritten();

    var file = try std.fs.cwd().createFile(F.path, .{});
    defer file.close();
    try file.writeAll(bytes);

    var result_buf: [128]u8 = undefined;
    var response = engine.Response.init(.hash, &result_buf);
    var request = engine.Request{ .operation = .hash, .codec = .binary, .payload = bytes };
    // The engine decodes the package into scratch; an arena contains the
    // allocations, matching the worker's service loop.
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    try engine.process(&request, &response, arena.allocator());

    const stdout = std.io.getStdOut().writer();
    try stdout.print("wrote {s} ({d} bytes)\n", .{ F.path, bytes.len });
    if (response.status != .ok) {
        try stdout.print("hash failed: {s}\n", .{@tagName(response.status)});
        std.process.exit(1);
    }
    try stdout.print("digest: {s}\n", .{std.fmt.bytesToHex(response.slice()[0..32], .lower)});
}
