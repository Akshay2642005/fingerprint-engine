//! Worker pool for the HTTP ingress (S4-d, story s4-ingress-http).
//!
//! The ingress is a TCP *client* to the workers: it holds long-lived pooled
//! `adapter.TcpClient`s and exchanges FPKG frames over them. The worker
//! serves one connection at a time but many sequential requests per
//! connection, so one slot per worker seed is the concurrency unit for a
//! single request; the pool round-robins across seeds and lazily connects on
//! first use, so a dead seed costs nothing until it is asked to work.
//!
//! Retry policy: each request is attempted once per slot in round-robin
//! order. Workers are stateless and deterministic (design §7, D16) — any
//! worker can process any package — so re-routing after a connect/write
//! failure is safe. A slot whose exchange failed is closed and reconnected
//! lazily on its next use, so the pool self-heals when a worker restarts.

const std = @import("std");
const adapter = @import("adapter");

/// Upper bound on a single connect attempt (a dead or unreachable worker
/// cannot wedge a request).
pub const connect_timeout_ns: u64 = 5 * std.time.ns_per_s;

/// Per-frame-stage receive deadline on pooled connections (H-1). The worker
/// replies in milliseconds; anything slower than this is wedged or gone.
pub const read_timeout_ns: u64 = 10 * std.time.ns_per_s;

pub const WorkerPool = struct {
    allocator: std.mem.Allocator,
    slots: []Slot,
    /// Round-robin cursor; advances on success so traffic spreads across
    /// seeds.
    next: usize = 0,

    /// Creates one slot per worker seed (`host:port` strings; the caller
    /// keeps them alive for the pool's lifetime).
    pub fn init(allocator: std.mem.Allocator, workers: []const []const u8) !WorkerPool {
        const slots = try allocator.alloc(Slot, workers.len);
        errdefer allocator.free(slots);
        for (slots, workers) |*slot, seed| {
            const host, const port = splitHostPort(seed) catch return error.InvalidWorker;
            slot.* = .{ .host = host, .port = port };
        }
        return .{ .allocator = allocator, .slots = slots };
    }

    pub fn deinit(self: *WorkerPool) void {
        for (self.slots) |*slot| {
            if (slot.client) |*c| c.close();
        }
        self.allocator.free(self.slots);
        self.slots = &.{};
    }

    /// Forwards one request frame to a worker and returns the full reply
    /// frame, allocated from `allocator` (owned by the caller). Every slot
    /// is attempted once in round-robin order; the last failure is returned
    /// when no worker is reachable.
    pub fn request(self: *WorkerPool, allocator: std.mem.Allocator, frame: []const u8) ![]const u8 {
        const n = self.slots.len;
        if (n == 0) return error.NoWorkers;
        var last_err: ?anyerror = null;
        for (0..n) |i| {
            const idx = (self.next + i) % n;
            const slot = &self.slots[idx];
            const reply = self.exchange(slot, allocator, frame) catch |err| {
                last_err = err;
                // The connection is broken (or the worker is dead): drop it
                // so the next attempt reconnects.
                if (slot.client) |*c| c.close();
                slot.client = null;
                continue;
            };
            self.next = (idx + 1) % n;
            return reply;
        }
        return last_err orelse error.NoWorkers;
    }

    /// One frame exchange over `slot`'s connection, connecting lazily.
    fn exchange(self: *WorkerPool, slot: *Slot, allocator: std.mem.Allocator, frame: []const u8) ![]const u8 {
        _ = self;
        if (slot.client == null) {
            var client = try adapter.TcpClient.init(
                allocator,
                slot.host,
                slot.port,
                read_timeout_ns,
            );
            errdefer client.close();
            try client.connect(connect_timeout_ns);
            slot.client = client;
        }
        const c = &slot.client.?;
        try c.writeFrame(frame);
        return c.readFrame(allocator);
    }
};

const Slot = struct {
    host: []const u8,
    port: u16,
    client: ?adapter.TcpClient = null,
};

fn splitHostPort(seed: []const u8) !struct { []const u8, u16 } {
    const idx = std.mem.lastIndexOfScalar(u8, seed, ':') orelse return error.InvalidWorker;
    const host = seed[0..idx];
    const port = try std.fmt.parseInt(u16, seed[idx + 1 ..], 10);
    return .{ host, port };
}
