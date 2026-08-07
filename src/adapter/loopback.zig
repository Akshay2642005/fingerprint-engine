/// Loopback transport (design §7.2, D16): the in-process stand-in for the
/// real inbound path. Two modes:
///
///   .memory — inbound/outbound queues owned by the transport. Tests and the
///             benchmark harness enqueue request frames and take response
///             frames directly, no sockets involved.
///   .stdio  — stdin/stdout pipes. The worker process communicates with its
///             parent (or a container sidecar) one FPKG frame at a time.
///
/// Both modes move whole frames; the worker still owns request mapping.
const std = @import("std");
const io = @import("io");
const transport = @import("transport.zig");

pub const Mode = enum {
    memory,
    stdio,
};

pub const Loopback = struct {
    allocator: std.mem.Allocator,
    mode: Mode,
    inbound: std.ArrayListUnmanaged([]const u8) = .{},
    outbound: std.ArrayListUnmanaged([]const u8) = .{},

    pub fn init(allocator: std.mem.Allocator, mode: Mode) Loopback {
        return .{ .allocator = allocator, .mode = mode };
    }

    pub fn deinit(self: *Loopback) void {
        for (self.inbound.items) |frame| self.allocator.free(frame);
        self.inbound.deinit(self.allocator);
        for (self.outbound.items) |frame| self.allocator.free(frame);
        self.outbound.deinit(self.allocator);
    }

    /// Test helper: enqueue a request frame. The frame is copied; ownership
    /// transfers to `readFrame` on the next call.
    pub fn enqueueRequest(self: *Loopback, frame: []const u8) !void {
        const owned = try self.allocator.dupe(u8, frame);
        try self.inbound.append(self.allocator, owned);
    }

    /// Test helper: dequeue a response frame, transferring ownership to the
    /// caller, or null when the outbound queue is empty.
    pub fn takeResponse(self: *Loopback) ?[]const u8 {
        if (self.outbound.items.len == 0) return null;
        return self.outbound.orderedRemove(0);
    }

    /// One inbound FPKG frame. In .memory mode the queued copy is returned
    /// and ownership transfers to the caller; .stdio mode reads from stdin.
    pub fn readFrame(self: *Loopback, allocator: std.mem.Allocator) ![]const u8 {
        switch (self.mode) {
            .memory => {
                if (self.inbound.items.len == 0) return error.EndOfStream;
                return self.inbound.orderedRemove(0);
            },
            .stdio => return transport.readFrameFrom(std.io.getStdIn().reader(), allocator),
        }
    }

    pub fn writeFrame(self: *Loopback, frame: []const u8) !void {
        switch (self.mode) {
            .memory => {
                const owned = try self.allocator.dupe(u8, frame);
                try self.outbound.append(self.allocator, owned);
            },
            .stdio => try std.io.getStdOut().writeAll(frame),
        }
    }

    /// Outbound events are a v1 no-op for loopback (no downstream consumer).
    pub fn publish(self: *Loopback, payload: []const u8) !void {
        _ = self;
        _ = payload;
    }

    /// Poison-frame handling is a v1 no-op for loopback.
    pub fn ack(self: *Loopback, frame: []const u8) void {
        _ = self;
        _ = frame;
    }
};

comptime {
    transport.check(Loopback);
}
