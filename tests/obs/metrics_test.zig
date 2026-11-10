// story: m8-observability
//! Metrics registry tests (ADR-014): counter/gauge/histogram semantics,
//! comptime label indexing, atomic behaviour under concurrency, and the exact
//! Prometheus text exposition. The golden render is the contract the scrape
//! listener will serve, so drift in the wire format is a test failure rather
//! than a scraping surprise.

const std = @import("std");
const testing = std.testing;
const obs = @import("obs");

const metrics = obs.metrics;

const StatusClass = enum { @"2xx", @"4xx", @"5xx" };
const Codec = enum { binary, json };

const duration_bounds = [_]f64{ 0.5, 1.0 };
const byte_bounds = [_]f64{ 1.0, 2.0 };

test "metrics: counter counts incrementally and in batches" {
    var counter = metrics.Counter(){};
    try testing.expectEqual(@as(u64, 0), counter.get());

    counter.inc();
    counter.inc();
    counter.add(40);
    try testing.expectEqual(@as(u64, 42), counter.get());

    // Adding zero is a no-op, not a wakeup.
    counter.add(0);
    try testing.expectEqual(@as(u64, 42), counter.get());
}

test "metrics: gauge sets and moves in both directions" {
    var gauge = metrics.Gauge(){};

    gauge.set(10);
    try testing.expectEqual(@as(i64, 10), gauge.get());

    gauge.inc();
    gauge.add(4);
    gauge.dec();
    try testing.expectEqual(@as(i64, 14), gauge.get());

    gauge.set(-3);
    try testing.expectEqual(@as(i64, -3), gauge.get());
}

test "metrics: labelled counter keeps series isolated" {
    const Labels = struct { status: StatusClass };
    var counter = metrics.CounterLabeled(Labels){};

    counter.inc(.{ .status = .@"2xx" });
    counter.inc(.{ .status = .@"2xx" });
    counter.add(.{ .status = .@"5xx" }, 7);

    try testing.expectEqual(@as(u64, 2), counter.get(.{ .status = .@"2xx" }));
    try testing.expectEqual(@as(u64, 0), counter.get(.{ .status = .@"4xx" }));
    try testing.expectEqual(@as(u64, 7), counter.get(.{ .status = .@"5xx" }));

    // `getAt` is the renderer's view: series order follows declaration order.
    try testing.expectEqual(@as(u64, 2), counter.getAt(0));
    try testing.expectEqual(@as(u64, 0), counter.getAt(1));
    try testing.expectEqual(@as(u64, 7), counter.getAt(2));
}

test "metrics: histogram buckets use inclusive le bounds" {
    var histogram = metrics.Histogram(&duration_bounds){};

    histogram.observe(0.5); // exactly at the first bound -> le 0.5
    histogram.observe(0.75); // -> le 1
    histogram.observe(1.0); // exactly at the second bound -> le 1
    histogram.observe(2.0); // -> +Inf

    try testing.expectEqual(@as(u64, 1), histogram.bucketAt(0, 0));
    try testing.expectEqual(@as(u64, 2), histogram.bucketAt(0, 1));
    try testing.expectEqual(@as(u64, 1), histogram.bucketAt(0, 2));
    try testing.expectEqual(@as(u64, 4), histogram.countAt(0));
    try testing.expectEqual(@as(f64, 4.25), histogram.sumAt(0));
}

test "metrics: labelled histogram scores each series independently" {
    const Labels = struct { codec: Codec };
    var histogram = metrics.HistogramLabeled(Labels, &byte_bounds){};

    histogram.observe(.{ .codec = .binary }, 1.0); // le 1
    histogram.observe(.{ .codec = .binary }, 5.0); // +Inf
    histogram.observe(.{ .codec = .json }, 1.5); // le 2

    try testing.expectEqual(@as(u64, 1), histogram.bucketAt(0, 0));
    try testing.expectEqual(@as(u64, 0), histogram.bucketAt(0, 1));
    try testing.expectEqual(@as(u64, 1), histogram.bucketAt(0, 2));
    try testing.expectEqual(@as(u64, 2), histogram.countAt(0));
    try testing.expectEqual(@as(f64, 6.0), histogram.sumAt(0));

    try testing.expectEqual(@as(u64, 0), histogram.bucketAt(1, 0));
    try testing.expectEqual(@as(u64, 1), histogram.bucketAt(1, 1));
    try testing.expectEqual(@as(u64, 0), histogram.bucketAt(1, 2));
    try testing.expectEqual(@as(u64, 1), histogram.countAt(1));
    try testing.expectEqual(@as(f64, 1.5), histogram.sumAt(1));
}

test "metrics: label index and labelsAt are inverses" {
    const Labels = struct { op: enum { a, b }, result: enum { ok, err } };
    const info = metrics.LabelInfo(Labels);

    try testing.expectEqual(@as(usize, 4), info.count);
    try testing.expectEqual(@as(usize, 0), info.index(.{ .op = .a, .result = .ok }));
    try testing.expectEqual(@as(usize, 1), info.index(.{ .op = .a, .result = .err }));
    try testing.expectEqual(@as(usize, 2), info.index(.{ .op = .b, .result = .ok }));
    try testing.expectEqual(@as(usize, 3), info.index(.{ .op = .b, .result = .err }));

    inline for (0..info.count) |series| {
        try testing.expectEqual(series, info.index(info.labelsAt(series)));
    }
}

test "metrics: render emits the Prometheus text format" {
    const Registry = struct {
        requests_total: metrics.CounterLabeled(struct { status: StatusClass }) = .{},
        replay_cache_entries: metrics.Gauge() = .{},
        duration_seconds: metrics.Histogram(&duration_bounds) = .{},
        bytes: metrics.HistogramLabeled(struct { codec: Codec }, &byte_bounds) = .{},
        not_a_metric: u64 = 5,
    };

    var registry = Registry{};
    registry.requests_total.inc(.{ .status = .@"2xx" });
    registry.requests_total.add(.{ .status = .@"2xx" }, 2);
    registry.replay_cache_entries.set(7);

    registry.duration_seconds.observe(0.25);
    registry.duration_seconds.observe(0.75);
    registry.duration_seconds.observe(1.5);

    registry.bytes.observe(.{ .codec = .binary }, 0.5);
    registry.bytes.observe(.{ .codec = .binary }, 3.0);
    registry.bytes.observe(.{ .codec = .json }, 1.5);

    var buffer: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    try metrics.render("fpkg_ingress_", &registry, stream.writer());

    const expected =
        \\# TYPE fpkg_ingress_requests_total counter
        \\fpkg_ingress_requests_total{status="2xx"} 3
        \\fpkg_ingress_requests_total{status="4xx"} 0
        \\fpkg_ingress_requests_total{status="5xx"} 0
        \\# TYPE fpkg_ingress_replay_cache_entries gauge
        \\fpkg_ingress_replay_cache_entries 7
        \\# TYPE fpkg_ingress_duration_seconds histogram
        \\fpkg_ingress_duration_seconds_bucket{le="0.5"} 1
        \\fpkg_ingress_duration_seconds_bucket{le="1"} 2
        \\fpkg_ingress_duration_seconds_bucket{le="+Inf"} 1
        \\fpkg_ingress_duration_seconds_sum 2.5
        \\fpkg_ingress_duration_seconds_count 3
        \\# TYPE fpkg_ingress_bytes histogram
        \\fpkg_ingress_bytes_bucket{codec="binary",le="1"} 1
        \\fpkg_ingress_bytes_bucket{codec="binary",le="2"} 1
        \\fpkg_ingress_bytes_bucket{codec="binary",le="+Inf"} 1
        \\fpkg_ingress_bytes_sum{codec="binary"} 3.5
        \\fpkg_ingress_bytes_count{codec="binary"} 2
        \\fpkg_ingress_bytes_bucket{codec="json",le="1"} 0
        \\fpkg_ingress_bytes_bucket{codec="json",le="2"} 1
        \\fpkg_ingress_bytes_bucket{codec="json",le="+Inf"} 0
        \\fpkg_ingress_bytes_sum{codec="json"} 1.5
        \\fpkg_ingress_bytes_count{codec="json"} 1
        \\
    ;

    try testing.expectEqualStrings(expected, stream.getWritten());
}

test "metrics: render ignores non-metric fields" {
    const Registry = struct { version: u32 = 1 };
    var registry = Registry{};

    var buffer: [64]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    try metrics.render("fpkg_worker_", &registry, stream.writer());
    try testing.expectEqualStrings("", stream.getWritten());
}

test "metrics: concurrent increments are not lost" {
    var counter = metrics.Counter(){};
    const thread_count = 4;
    const per_thread = 5000;

    var threads: [thread_count]std.Thread = undefined;
    for (&threads) |*thread| {
        thread.* = try std.Thread.spawn(.{}, struct {
            fn run(target: *metrics.Counter(), iterations: usize) void {
                var i: usize = 0;
                while (i < iterations) : (i += 1) target.inc();
            }
        }.run, .{ &counter, per_thread });
    }
    for (threads) |thread| thread.join();

    try testing.expectEqual(@as(u64, thread_count * per_thread), counter.get());
}
