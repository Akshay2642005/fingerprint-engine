/// Shared I/O and timing utilities for benchmarks.
/// Wraps Zig 0.16.0's std.Io.Threaded for cross-platform timing.

const std = @import("std");

pub const BenchIo = struct {
    threaded: std.Io.Threaded,

    pub fn init(allocator: std.mem.Allocator) BenchIo {
        return .{
            .threaded = std.Io.Threaded.init(allocator, .{}),
        };
    }

    pub fn deinit(self: *BenchIo) void {
        self.threaded.deinit();
    }

    pub fn io(self: *BenchIo) std.Io {
        return self.threaded.io();
    }

    pub fn timestamp(self: *BenchIo) std.Io.Timestamp {
        return std.Io.Timestamp.now(self.io(), .awake);
    }

    pub fn elapsed(self: *BenchIo, from: std.Io.Timestamp) u64 {
        const now = std.Io.Timestamp.now(self.io(), .awake);
        const dur = std.Io.Timestamp.durationTo(from, now);
        return @intCast(dur.nanoseconds);
    }
};
