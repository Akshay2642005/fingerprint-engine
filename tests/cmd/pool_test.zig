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

/// Short connect budget so a refused seed cannot slow the suite down.
const probe_timeout_ns: u64 = 200 * std.time.ns_per_ms;

fn refreshWith(workers: *pool.WorkerPool, alloc: std.mem.Allocator, stale_after_ns: u64) usize {
    return workers.refresh(alloc, .{
        .timeout_ns = probe_timeout_ns,
        .stale_after_ns = stale_after_ns,
    });
}

/// A stand-in worker: a listening socket the pool can connect to, plus the
/// seed string that points at it. The pool only needs the TCP handshake to
/// count a slot as live, so no FPKG exchange is required.
const StubWorker = struct {
    listener: std.net.Server,
    seed: []u8,
    alive: bool = true,

    fn start(alloc: std.mem.Allocator) !StubWorker {
        const address = try std.net.Address.parseIp("127.0.0.1", 0);
        var listener = try address.listen(.{ .reuse_address = true });
        errdefer listener.deinit();
        const port = listener.listen_address.getPort();
        const seed = try std.fmt.allocPrint(alloc, "127.0.0.1:{d}", .{port});
        return .{ .listener = listener, .seed = seed };
    }

    /// Represents the worker process dying: the socket that would accept the
    /// pool's next connection is gone, while any established client socket
    /// stays allocated on the pool side. Idempotent so a failed assertion
    /// cannot leak the listener twice.
    fn kill(self: *StubWorker) void {
        if (!self.alive) return;
        self.alive = false;
        self.listener.deinit();
    }

    fn deinit(self: *StubWorker, alloc: std.mem.Allocator) void {
        self.kill();
        alloc.free(self.seed);
    }
};

test "pool: refresh drops a connection whose worker went away" {
    const alloc = testing.allocator;

    var stub = try StubWorker.start(alloc);
    defer stub.deinit(alloc);
    const seeds = [_][]const u8{stub.seed};

    var workers = try pool.WorkerPool.init(alloc, &seeds);
    defer workers.deinit();

    try testing.expectEqual(@as(usize, 1), refreshWith(&workers, alloc, pool.idle_probe_after_ns));

    // The worker dies after the pool connected. The pooled client still holds
    // its end of the socket, so `liveCount` keeps reporting a healthy slot —
    // the stale state the idle path used to publish forever.
    stub.kill();
    try testing.expectEqual(@as(usize, 1), workers.liveCount());

    // An expired TTL forces the re-probe: the reconnect fails, so the count
    // that feeds the readiness gauge drops to zero.
    try testing.expectEqual(@as(usize, 0), refreshWith(&workers, alloc, 0));
    try testing.expectEqual(@as(usize, 0), workers.liveCount());
}

test "pool: refresh trusts a connection younger than the readiness TTL" {
    const alloc = testing.allocator;

    var stub = try StubWorker.start(alloc);
    defer stub.deinit(alloc);
    const seeds = [_][]const u8{stub.seed};

    var workers = try pool.WorkerPool.init(alloc, &seeds);
    defer workers.deinit();

    try testing.expectEqual(@as(usize, 1), refreshWith(&workers, alloc, pool.idle_probe_after_ns));

    // Nothing has gone stale, so the tick must not churn the connection: if it
    // ignored the TTL and reconnected, the dropped listener would show up as
    // an unreachable seed. The boundary is the production TTL, not a literal,
    // so changing the constant changes the test.
    stub.kill();
    try testing.expectEqual(@as(usize, 1), refreshWith(&workers, alloc, pool.idle_probe_after_ns));
    try testing.expectEqual(
        @as(usize, 1),
        refreshWith(&workers, alloc, pool.idle_probe_after_ns - 1),
    );
}

test "pool: refresh reports zero when the seed was never reachable" {
    const alloc = testing.allocator;

    var stub = try StubWorker.start(alloc);
    defer stub.deinit(alloc);
    const seeds = [_][]const u8{stub.seed};
    stub.kill();

    var workers = try pool.WorkerPool.init(alloc, &seeds);
    defer workers.deinit();

    try testing.expectEqual(@as(usize, 0), refreshWith(&workers, alloc, pool.idle_probe_after_ns));
}

test "pool: a partially dead pool reports one live worker" {
    const alloc = testing.allocator;

    var healthy = try StubWorker.start(alloc);
    defer healthy.deinit(alloc);
    var dying = try StubWorker.start(alloc);
    defer dying.deinit(alloc);
    const seeds = [_][]const u8{ healthy.seed, dying.seed };

    var workers = try pool.WorkerPool.init(alloc, &seeds);
    defer workers.deinit();

    try testing.expectEqual(@as(usize, 2), refreshWith(&workers, alloc, pool.idle_probe_after_ns));

    // One worker dies while both sockets are held. Before the fix the ingress
    // only refreshed when the pool was completely empty, so this exact state
    // kept `/readyz` green forever with a dead seed in the pool.
    dying.kill();
    try testing.expectEqual(@as(usize, 1), refreshWith(&workers, alloc, 0));
    try testing.expectEqual(@as(usize, 1), workers.liveCount());
}

test "pool: an empty pool has no live workers and cannot be made live" {
    const alloc = testing.allocator;

    var workers = try pool.WorkerPool.init(alloc, &.{});
    defer workers.deinit();

    try testing.expectEqual(@as(usize, 0), refreshWith(&workers, alloc, pool.idle_probe_after_ns));
    try testing.expectEqual(@as(usize, 0), workers.liveCount());
}

test "pool: probe backoff doubles to the cap and resets on success" {
    var backoff = pool.ProbeBackoff{};
    try testing.expect(!backoff.active(0));

    backoff.recordFailure(1_000);
    try testing.expectEqual(pool.retry_base_ns, backoff.delay_ns);
    try testing.expect(backoff.active(1_000 + pool.retry_base_ns - 1));
    try testing.expect(!backoff.active(1_000 + pool.retry_base_ns));

    backoff.recordFailure(2_000);
    try testing.expectEqual(pool.retry_base_ns * 2, backoff.delay_ns);

    var i: usize = 0;
    while (i < 16) : (i += 1) backoff.recordFailure(3_000);
    try testing.expectEqual(pool.retry_max_ns, backoff.delay_ns);

    backoff.reset();
    try testing.expectEqual(@as(u64, 0), backoff.delay_ns);
    try testing.expect(!backoff.active(4_000));
}
