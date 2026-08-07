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

const usage =
    \\Usage:
    \\
    \\  zig build scripts -- [-h | --help]
    \\
    \\  zig build scripts -- help
    \\
;

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

    std.debug.print("unknown subcommand '{s}'\n\n{s}", .{ subcommand, usage });
    std.process.exit(1);
}
