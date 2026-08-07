/// Shared timing utilities for benchmarks.
/// Uses std.time.Timer for cross-platform nanosecond timing.
const std = @import("std");

pub const BenchIo = struct {
    timer: std.time.Timer,

    pub fn init(allocator: std.mem.Allocator) BenchIo {
        _ = allocator;
        return .{ .timer = std.time.Timer.start() catch @panic("timer") };
    }

    pub fn deinit(self: *BenchIo) void {
        _ = self;
    }

    pub fn timestamp(self: *BenchIo) u64 {
        return self.timer.read();
    }

    pub fn elapsed(self: *BenchIo, from: u64) u64 {
        return self.timer.read() - from;
    }
};
