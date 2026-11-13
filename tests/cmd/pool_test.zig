//! Worker-pool readiness tests (ADR-014 §5).
//!
//! `liveCount()` counts client objects, not reachability: a worker can die
//! while the pool still holds its socket, and the kernel keeps that socket
//! looking alive. These tests pin the re-probe in `refresh`, which is what the
//! ingress publishes to `fpkg_ingress_worker_pool_healthy` and what `/readyz`
//! answers from.

const std = @import("std");
const testing = std.testing;
const ingress = @import("ingress");

const pool = ingress.pool;

/// A stand-in worker: a listening socket the pool can connect to, plus the
/// seed string that points at it. The pool only needs the TCP handshake to
/// count a slot as live, so no FPKG exchange is required.
const StubWorker = struct {
    listener: std.net.Server,
    seed: []u8,

    fn start(alloc: std.mem.Allocator) !StubWorker {
        const address = try std.net.Address.parseIp("127.0.0.1", 0);
        var listener = try address.listen(.{ .reuse_address = true });
        errdefer listener.deinit();
        const seed = try std.fmt.allocPrint(alloc, "127.0.0.1:{d}", .{listener.listen_address.getPort()});
        return .{ .listener = listener, .seed = seed };
    }

    /// Represents the worker process dying: the socket that would accept the
    /// pool's next connection is gone, while any established client socket
    /// stays allocated on the pool side.
    fn kill(self: *StubWorker) void {
        self.listener.deinit();
    }
};

test "pool: refresh drops a connection whose worker went away" {
    const alloc = testing.allocator;

    var stub = try StubWorker.start(alloc);
    defer alloc.free(stub.seed);
    const seeds = [_][]const u8{stub.seed};

    var workers = try pool.WorkerPool.init(alloc, &seeds);
    defer workers.deinit();

    try testing.expectEqual(
        @as(usize, 1),
        workers.refresh(alloc, 500 * std.time.ns_per_ms, pool.idle_probe_after_ns),
    );

    // The worker dies after the pool connected. The pooled client still holds
    // its end of the socket, so `liveCount` keeps reporting a healthy slot —
    // the stale state the idle path used to publish forever.
    stub.kill();
    try testing.expectEqual(@as(usize, 1), workers.liveCount());

    // An expired TTL forces the re-probe: the reconnect fails, so the count
    // that feeds the readiness gauge drops to zero.
    try testing.expectEqual(
        @as(usize, 0),
        workers.refresh(alloc, 200 * std.time.ns_per_ms, 0),
    );
    try testing.expectEqual(@as(usize, 0), workers.liveCount());
}

test "pool: refresh trusts a connection younger than the readiness TTL" {
    const alloc = testing.allocator;

    var stub = try StubWorker.start(alloc);
    defer alloc.free(stub.seed);
    const seeds = [_][]const u8{stub.seed};

    var workers = try pool.WorkerPool.init(alloc, &seeds);
    defer workers.deinit();

    try testing.expectEqual(
        @as(usize, 1),
        workers.refresh(alloc, 500 * std.time.ns_per_ms, pool.idle_probe_after_ns),
    );

    // Nothing has gone stale, so the tick must not churn the connection: if it
    // ignored the TTL and reconnected, the dropped listener would show up as
    // an unreachable seed.
    stub.kill();
    try testing.expectEqual(
        @as(usize, 1),
        workers.refresh(alloc, 200 * std.time.ns_per_ms, 60 * std.time.ns_per_s),
    );
}

test "pool: refresh reports zero when the seed was never reachable" {
    const alloc = testing.allocator;

    var stub = try StubWorker.start(alloc);
    defer alloc.free(stub.seed);
    const seeds = [_][]const u8{stub.seed};
    stub.kill();

    var workers = try pool.WorkerPool.init(alloc, &seeds);
    defer workers.deinit();

    try testing.expectEqual(
        @as(usize, 0),
        workers.refresh(alloc, 200 * std.time.ns_per_ms, pool.idle_probe_after_ns),
    );
}
