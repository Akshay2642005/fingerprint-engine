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
const log = @import("log");

/// Upper bound on a single connect attempt (a dead or unreachable worker
/// cannot wedge a request).
pub const connect_timeout_ns: u64 = 5 * std.time.ns_per_s;

/// Per-frame-stage receive deadline on pooled connections (H-1). The worker
/// replies in milliseconds; anything slower than this is wedged or gone.
pub const read_timeout_ns: u64 = 10 * std.time.ns_per_s;

/// How long a pooled connection may sit unused before the health tick
/// re-probes it (readiness TTL, ADR-014 §5). A socket to a worker that died
/// while connected stays valid at the kernel level, so only a fresh connect
/// proves the seed is still reachable. Bounds `/readyz` staleness to this plus
/// one health tick.
///
/// The value is three `read_timeout_ns`: a worker that is merely slow still
/// answers within one frame deadline, so a TTL below that would churn healthy
/// connections. A slot that serves traffic is never re-probed — the exchange
/// stamps it — so the cost is at most one connect per worker per silent 30s.
/// Operators can lower it with `--readiness-ttl-ms` when a rollout needs
/// faster failure detection.
pub const idle_probe_after_ns: u64 = 3 * read_timeout_ns;

/// First delay before re-probing a seed whose connect failed, doubled per
/// consecutive failure up to `retry_max_ns`. Without it a dead seed costs one
/// `probe_timeout_ns` connect inside the accept loop on every health tick.
pub const retry_base_ns: u64 = 5 * std.time.ns_per_s;

/// Ceiling for the probe backoff.
pub const retry_max_ns: u64 = 60 * std.time.ns_per_s;

/// Knobs for `refresh`. Two bare `u64`s would let a caller transpose the
/// connect budget and the staleness horizon — 30s per connect against a 250ms
/// TTL — and still compile, so the pair travels as a struct with defaults.
pub const RefreshOptions = struct {
    /// Budget for one connect attempt.
    timeout_ns: u64 = connect_timeout_ns,
    /// Age at which a held connection stops counting as proof of liveness.
    stale_after_ns: u64 = idle_probe_after_ns,
};

/// Exponential backoff for one seed's readiness probe. Kept as a value type
/// so the schedule (first delay, doubling, cap, reset) is testable without a
/// socket.
pub const ProbeBackoff = struct {
    /// When the last probe failed.
    failed_at_ns: u64 = 0,
    /// Current suppression window; 0 means "not backing off".
    delay_ns: u64 = 0,

    /// True while a failed probe still suppresses the next one.
    pub fn active(self: *const ProbeBackoff, now_ns: u64) bool {
        if (self.delay_ns == 0) return false;
        return now_ns -% self.failed_at_ns < self.delay_ns;
    }

    /// Doubles the delay on every consecutive failure, capped at
    /// `retry_max_ns`, so a long-dead seed is probed about once a minute.
    pub fn recordFailure(self: *ProbeBackoff, now_ns: u64) void {
        self.failed_at_ns = now_ns;
        self.delay_ns = if (self.delay_ns == 0)
            retry_base_ns
        else
            @min(self.delay_ns * 2, retry_max_ns);
    }

    /// Any successful connect or exchange proves the seed is healthy again.
    pub fn reset(self: *ProbeBackoff) void {
        self.delay_ns = 0;
    }
};

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
        for (slots, workers, 0..) |*slot, seed, id| {
            const host, const port = splitHostPort(seed) catch return error.InvalidWorker;
            slot.* = .{ .id = id, .host = host, .port = port };
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
                log.pool.warn(
                    "pool: worker {d} ({s}:{d}) unavailable ({s}), retrying next slot",
                    .{ slot.id, slot.host, slot.port, @errorName(err) },
                );
                if (slot.client) |*c| c.close();
                slot.client = null;
                continue;
            };
            self.next = (idx + 1) % n;
            return reply;
        }
        log.pool.warn("pool: no workers reachable", .{});
        return last_err orelse error.NoWorkers;
    }

    /// One frame exchange over `slot`'s connection, connecting lazily.
    fn exchange(self: *WorkerPool, slot: *Slot, allocator: std.mem.Allocator, frame: []const u8) ![]const u8 {
        if (slot.client == null) try self.connectSlot(slot, allocator, connect_timeout_ns);
        const c = &slot.client.?;
        log.pool.debug("pool: forwarding signal package to worker {d} ({s}:{d})", .{ slot.id, slot.host, slot.port });
        try c.writeFrame(frame);
        const reply = try c.readFrame(allocator);
        // A completed exchange is the strongest liveness signal the pool has;
        // stamp it so the readiness re-probe stays off this slot's back.
        slot.recordSuccess(nowNs());
        log.pool.debug("pool: reply from worker {d} ({s}:{d}) ({d} bytes)", .{ slot.id, slot.host, slot.port, reply.len });
        return reply;
    }

    /// Connects one slot if it has no live client. The connection is kept and
    /// reused by the next request, so a probe is never throwaway work.
    fn connectSlot(self: *WorkerPool, slot: *Slot, allocator: std.mem.Allocator, timeout_ns: u64) !void {
        _ = self;
        var client = try adapter.TcpClient.init(
            allocator,
            slot.host,
            slot.port,
            read_timeout_ns,
        );
        errdefer client.close();
        try client.connect(timeout_ns);
        log.pool.info("pool: connected to worker {d} ({s}:{d})", .{ slot.id, slot.host, slot.port });
        slot.client = client;
        slot.recordSuccess(nowNs());
    }

    /// Slots holding a live client. Unsynchronized: only the accept thread may
    /// call this (ADR-014 readiness is published through the atomic gauge).
    pub fn liveCount(self: *const WorkerPool) usize {
        var live: usize = 0;
        for (self.slots) |slot| {
            if (slot.client != null) live += 1;
        }
        return live;
    }

    /// Connects every slot that has no client, and re-probes every slot whose
    /// connection has been idle for at least `options.stale_after_ns`, bounded
    /// by `options.timeout_ns` per slot. Returns the number of slots now live.
    ///
    /// `liveCount` alone is not readiness: a worker that died while the pool
    /// held its connection leaves a non-null client behind until the next
    /// request fails. Reconnecting an idle slot is the only cheap proof that
    /// the seed's host still answers, so `/readyz` cannot stay green on a stale
    /// socket (ADR-014 §5). A failed probe backs the slot off, because this
    /// runs inside the accept loop: without it a dead seed would cost
    /// `timeout_ns` of request latency on every tick.
    pub fn refresh(
        self: *WorkerPool,
        allocator: std.mem.Allocator,
        options: RefreshOptions,
    ) usize {
        const now = nowNs();
        for (self.slots) |*slot| {
            if (slot.backoff.active(now)) continue;
            if (slot.client) |*client| {
                if (!slot.isStale(now, options.stale_after_ns)) continue;
                // Drop the old connection before probing so a half-open socket
                // can never be mistaken for a reachable worker.
                client.close();
                slot.client = null;
            }
            self.connectSlot(slot, allocator, options.timeout_ns) catch |err| {
                slot.backoff.recordFailure(now);
                log.pool.warn(
                    "pool: readiness probe failed for worker {d} ({s}:{d}): {s}",
                    .{ slot.id, slot.host, slot.port, @errorName(err) },
                );
            };
        }
        return self.liveCount();
    }
};

/// Wall-clock nanoseconds, clamped at zero so a pre-epoch clock cannot wrap
/// the staleness comparison. Only differences matter, and the probe horizon
/// (seconds) is far above any clock adjustment.
///
/// Shared with the accept loop, which time-gates the health tick on the same
/// clock so the tick cannot be starved by a steady stream of connections.
pub fn nowNs() u64 {
    const timestamp = std.time.nanoTimestamp();
    if (timestamp < 0) return 0;
    return @intCast(timestamp);
}

const Slot = struct {
    /// Stable worker index (0-based `--worker=` seed position) used in logs
    /// as `worker_id` so operators can correlate a request to its worker.
    id: usize,
    host: []const u8,
    port: u16,
    client: ?adapter.TcpClient = null,
    /// When this slot last connected or completed an exchange (`nowNs`).
    /// Drives the readiness re-probe in `refresh`.
    last_used_ns: u64 = 0,
    /// Suppresses probing a seed whose connect keeps failing.
    backoff: ProbeBackoff = .{},

    /// True when the slot has gone `stale_after_ns` without useful work. The
    /// wrapping subtraction treats a backwards clock jump as "stale", which
    /// costs at most one extra reconnect.
    fn isStale(self: *const Slot, now_ns: u64, stale_after_ns: u64) bool {
        return now_ns -% self.last_used_ns >= stale_after_ns;
    }

    /// Any successful connect or exchange resets the backoff: readiness should
    /// follow a recovered worker without waiting out the delay.
    fn recordSuccess(self: *Slot, now_ns: u64) void {
        self.last_used_ns = now_ns;
        self.backoff.reset();
    }
};

fn splitHostPort(seed: []const u8) !struct { []const u8, u16 } {
    // R-7: support IPv6 bracket notation "[::1]:8080" in addition to IPv4 "0.0.0.0:8080".
    if (seed.len > 0 and seed[0] == '[') {
        const close = std.mem.indexOfScalar(u8, seed, ']') orelse return error.InvalidWorker;
        if (close + 1 >= seed.len or seed[close + 1] != ':') return error.InvalidWorker;
        const host = seed[1..close];
        const port = try std.fmt.parseInt(u16, seed[close + 2 ..], 10);
        return .{ host, port };
    }
    const idx = std.mem.lastIndexOfScalar(u8, seed, ':') orelse return error.InvalidWorker;
    const host = seed[0..idx];
    const port = try std.fmt.parseInt(u16, seed[idx + 1 ..], 10);
    return .{ host, port };
}
