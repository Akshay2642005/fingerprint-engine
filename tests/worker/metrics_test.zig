//! Worker metric registry tests (ADR-014 §2, story m8-observability).
//!
//! The registry is a declaration, so the tests pin the wire contract the
//! scrape endpoint and the alert rules depend on: metric names, the label
//! sets, the histogram buckets, and the two mapping helpers (engine operation
//! and drop reason) being total.

const std = @import("std");
const testing = std.testing;
const worker = @import("worker");

const metrics = worker.metrics;

test "worker metrics: the registry renders the ADR-014 catalog" {
    var registry = metrics.Metrics{};
    registry.observeJob(.package, .ok, 0.003);
    registry.publish_total.inc(.{ .result = .acked });
    registry.frames_dropped_total.inc(.{ .reason = .bad_magic });
    registry.signals_present.observe(57);
    registry.entropy.observe(180);
    registry.risk_score.observe(0.42);
    registry.amqp_connected.set(1);

    var buffer: [64 * 1024]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    try metrics.render(&registry, stream.writer().any());
    const text = stream.getWritten();

    // `package` is series 8 of 10 in the op label; the exact line proves the
    // stride/inversion contract, not just that the name appears somewhere.
    try testing.expect(std.mem.indexOf(u8, text, "# TYPE fpkg_worker_jobs_total counter\n") != null);
    try testing.expect(std.mem.indexOf(u8, text, "fpkg_worker_jobs_total{op=\"package\",result=\"ok\"} 1\n") != null);
    try testing.expect(std.mem.indexOf(u8, text, "fpkg_worker_jobs_total{op=\"hash\",result=\"ok\"} 0\n") != null);
    try testing.expect(std.mem.indexOf(u8, text, "fpkg_worker_jobs_total{op=\"unknown\",result=\"error\"} 0\n") != null);
    try testing.expect(std.mem.indexOf(u8, text, "# TYPE fpkg_worker_job_duration_seconds histogram\n") != null);
    try testing.expect(std.mem.indexOf(u8, text, "fpkg_worker_job_duration_seconds_count{op=\"package\"} 1\n") != null);
    try testing.expect(std.mem.indexOf(u8, text, "fpkg_worker_job_duration_seconds_bucket{op=\"package\",le=\"0.0005\"} 0\n") != null);
    try testing.expect(std.mem.indexOf(u8, text, "fpkg_worker_job_duration_seconds_bucket{op=\"package\",le=\"0.005\"} 1\n") != null);
    try testing.expect(std.mem.indexOf(u8, text, "fpkg_worker_publish_total{result=\"acked\"} 1\n") != null);
    // The ADR-016 outcomes exist (and read 0) before the dead-letter path
    // lands, so alert rules can be written against stable series.
    try testing.expect(std.mem.indexOf(u8, text, "fpkg_worker_publish_total{result=\"dlq\"} 0\n") != null);
    try testing.expect(std.mem.indexOf(u8, text, "fpkg_worker_publish_total{result=\"unroutable\"} 0\n") != null);
    try testing.expect(std.mem.indexOf(u8, text, "fpkg_worker_frames_dropped_total{reason=\"bad_magic\"} 1\n") != null);
    try testing.expect(std.mem.indexOf(u8, text, "fpkg_worker_frames_dropped_total{reason=\"other\"} 0\n") != null);
    try testing.expect(std.mem.indexOf(u8, text, "fpkg_worker_signals_present_bucket{le=\"64\"} 1\n") != null);
    try testing.expect(std.mem.indexOf(u8, text, "fpkg_worker_entropy_bucket{le=\"192\"} 1\n") != null);
    try testing.expect(std.mem.indexOf(u8, text, "fpkg_worker_risk_score_bucket{le=\"0.5\"} 1\n") != null);
    try testing.expect(std.mem.indexOf(u8, text, "fpkg_worker_amqp_connected 1\n") != null);

    // Preamble metrics belong to the scrape listener, never the registry.
    try testing.expect(std.mem.indexOf(u8, text, "fpkg_worker_build_info") == null);
    try testing.expect(std.mem.indexOf(u8, text, "fpkg_worker_ready") == null);
}

test "worker metrics: engine operations and drop reasons map totally" {
    const expect = testing.expectEqual;
    try expect(metrics.Op.validate, metrics.opOf(.validate));
    try expect(metrics.Op.normalize, metrics.opOf(.normalize));
    try expect(metrics.Op.serialize, metrics.opOf(.serialize));
    try expect(metrics.Op.deserialize, metrics.opOf(.deserialize));
    try expect(metrics.Op.hash, metrics.opOf(.hash));
    try expect(metrics.Op.entropy, metrics.opOf(.entropy));
    try expect(metrics.Op.similarity, metrics.opOf(.similarity));
    try expect(metrics.Op.risk, metrics.opOf(.risk));
    try expect(metrics.Op.package, metrics.opOf(.package));
    // A future operation is counted as `unknown` rather than producing an
    // unnamed label value the renderer cannot print.
    try expect(metrics.Op.unknown, metrics.opOf(@as(@import("engine").Operation, @enumFromInt(200))));

    try expect(metrics.DropReason.bad_magic, metrics.dropReasonOf(error.InvalidMagic));
    try expect(metrics.DropReason.integrity, metrics.dropReasonOf(error.IntegrityViolation));
    try expect(metrics.DropReason.decode, metrics.dropReasonOf(error.Truncated));
    try expect(metrics.DropReason.decode, metrics.dropReasonOf(error.UnsupportedVersion));
    try expect(metrics.DropReason.decode, metrics.dropReasonOf(error.SessionIdTooLong));
    try expect(metrics.DropReason.other, metrics.dropReasonOf(error.OutOfMemory));
}
