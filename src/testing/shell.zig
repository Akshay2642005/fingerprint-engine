//! Minimal subprocess helper for integration and end-to-end tests.
//!
//! Spawn an executable, optionally feed its stdin, capture stdout and
//! stderr, and assert its exit status.
//!
//! This file must stay independent of the rest of the codebase: the
//! integration test binary (src/integration_tests.zig) contains no engine
//! code and only interacts with the engine through pre-built executables.
const std = @import("std");

const Shell = @This();

gpa: std.mem.Allocator,

/// Captured stdout/stderr buffers are owned by this arena and stay valid
/// until the shell is destroyed.
arena: std.heap.ArenaAllocator,

pub const Result = struct {
    exit_code: u8,
    stdout: []const u8,
    stderr: []const u8,
};

pub fn create(gpa: std.mem.Allocator) !*Shell {
    var arena = std.heap.ArenaAllocator.init(gpa);
    errdefer arena.deinit();
    const shell = try gpa.create(Shell);
    errdefer gpa.destroy(shell);
    shell.* = .{ .gpa = gpa, .arena = arena };
    return shell;
}

pub fn destroy(shell: *Shell) void {
    const gpa = shell.gpa;
    shell.arena.deinit();
    gpa.destroy(shell);
}

/// Run `argv`, feed `options.stdin` (if any), and capture stdout and stderr.
/// The process must exit with `expected_exit_code` (default 0), otherwise
/// `error.ExitStatus` is returned.
///
/// `stdin` is written synchronously before the output is drained, so it must
/// be small enough to fit the pipe buffer without deadlocking (the child
/// blocking on a full stdout/stderr pipe while we are still writing).
pub fn exec(shell: *Shell, argv: []const []const u8, options: struct {
    stdin: ?[]const u8 = null,
    expected_exit_code: u8 = 0,
    max_output_bytes: usize = 4 * 1024 * 1024,
}) !Result {
    var child = std.process.Child.init(argv, shell.gpa);
    child.stdin_behavior = if (options.stdin != null) .Pipe else .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    try child.spawn();
    errdefer _ = child.kill() catch {};

    if (options.stdin) |stdin| {
        try child.stdin.?.writeAll(stdin);
        child.stdin.?.close();
        // wait() would close stdin again; it is already back in the OS's hands.
        child.stdin = null;
    }

    var stdout = std.ArrayListUnmanaged(u8){};
    defer stdout.deinit(shell.gpa);
    var stderr = std.ArrayListUnmanaged(u8){};
    defer stderr.deinit(shell.gpa);
    try child.collectOutput(shell.gpa, &stdout, &stderr, options.max_output_bytes);

    const term = try child.wait();
    const exit_code: u8 = switch (term) {
        .Exited => |code| code,
        else => return error.ProcessTerminated,
    };
    if (exit_code != options.expected_exit_code) return error.ExitStatus;

    return .{
        .exit_code = exit_code,
        .stdout = try shell.arena.allocator().dupe(u8, stdout.items),
        .stderr = try shell.arena.allocator().dupe(u8, stderr.items),
    };
}
