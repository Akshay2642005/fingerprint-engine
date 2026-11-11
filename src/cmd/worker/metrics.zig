//! Worker metric registry (ADR-014 §2, story m8-observability).
//!
//! The catalog lives in `specs/architecture/observability.md` §Worker. This
//! file is only the declaration plus the two mapping helpers; `obs.metrics`
//! owns the storage and the exposition, and `obs.scrape` serves it on
//! `--metrics-listen`.
//!
//! `fpkg_worker_build_info` and `fpkg_worker_ready` are **not** fields here:
//! the scrape listener emits both from its own preamble, and declaring them in
//! the registry too would emit duplicate `# TYPE` lines.
//!
//! The label enums are exhaustive and local on purpose. `engine.Operation` is
//! non-exhaustive (it carries a `_` hole for forward compatibility), and the
//! renderer rebuilds label text with `@tagName` from `@enumFromInt`, which is
//! not legal for an unnamed non-exhaustive value. A separate enum also makes a
//! new engine operation a compile error here rather than a silently missing
//! series.

const std = @import("std");
const engine = @import("engine");
const obs = @import("obs");

/// Engine operation as a metric label (`op`).
pub const Op = enum {
    validate,
    normalize,
    serialize,
    deserialize,
    hash,
    entropy,
    similarity,
    risk,
    package,
    /// A frame that decoded but maps to no engine operation.
    unknown,
};

/// Did the operation succeed? `error` is any non-`ok` engine status, plus a
/// raised error from the engine itself.
pub const JobResult = enum { ok, @"error" };

/// Outcome of one broker publish. `acked` and `failed` are the only two that
/// can occur until ADR-016 lands in Week 11; `unroutable`, `dlq` and
/// `dlq_failed` are declared now so the series exist (and read 0) from the
/// first scrape, and the alert rules can be written against them.
pub const PublishResult = enum { acked, unroutable, dlq, dlq_failed, failed };

/// Why an inbound frame was dropped before reaching the engine.
pub const DropReason = enum { bad_magic, integrity, decode, other };

/// Per-operation service time, in seconds (observability.md §Worker).
pub const duration_buckets = [_]f64{
    0.0005, 0.001, 0.0025, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1,
};

/// Features present per package. The top bucket is the registry size (102),
/// so a fully covered package lands in the last finite bucket rather than
/// `+Inf`.
pub const signals_buckets = [_]f64{ 0, 8, 16, 32, 48, 64, 80, 96, 102 };

/// Emitted entropy estimate, in bits.
pub const entropy_buckets = [_]f64{ 0, 16, 32, 64, 96, 128, 160, 192, 224, 256 };

/// Emitted risk score (0..1).
pub const risk_buckets = [_]f64{ 0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0 };

/// The worker registry. One instance per process; the scrape thread reads it
/// while the serve loop writes, which is why every field is atomic.
pub const Metrics = struct {
    jobs_total: obs.metrics.CounterLabeled(struct { op: Op, result: JobResult }) = .{},
    job_duration_seconds: obs.metrics.HistogramLabeled(struct { op: Op }, &duration_buckets) = .{},
    signals_present: obs.metrics.Histogram(&signals_buckets) = .{},
    entropy: obs.metrics.Histogram(&entropy_buckets) = .{},
    risk_score: obs.metrics.Histogram(&risk_buckets) = .{},
    publish_total: obs.metrics.CounterLabeled(struct { result: PublishResult }) = .{},
    frames_dropped_total: obs.metrics.CounterLabeled(struct { reason: DropReason }) = .{},
    amqp_connected: obs.metrics.Gauge() = .{},

    /// One completed engine call: the counter and its latency sample move
    /// together, so a dashboard can never see an operation that has a
    /// duration but no count.
    pub fn observeJob(self: *Metrics, op: Op, result: JobResult, elapsed_seconds: f64) void {
        self.jobs_total.inc(.{ .op = op, .result = result });
        self.job_duration_seconds.observe(.{ .op = op }, elapsed_seconds);
    }
};

/// Metric label for an engine operation.
pub fn opOf(operation: engine.Operation) Op {
    return switch (operation) {
        .validate => .validate,
        .normalize => .normalize,
        .serialize => .serialize,
        .deserialize => .deserialize,
        .hash => .hash,
        .entropy => .entropy,
        .similarity => .similarity,
        .risk => .risk,
        .package => .package,
        _ => .unknown,
    };
}

/// Metric category for a dropped inbound frame. The three named reasons are
/// the ones an operator acts on differently (wrong port, corrupt body,
/// version/schema skew); everything else is `other` rather than growing with
/// the error set.
pub fn dropReasonOf(err: anyerror) DropReason {
    return switch (err) {
        error.InvalidMagic => .bad_magic,
        error.IntegrityViolation => .integrity,
        error.Truncated,
        error.PayloadTooLarge,
        error.UnsupportedVersion,
        error.InvalidReserved,
        error.InvalidMessageType,
        error.InvalidCodec,
        error.InvalidStatus,
        error.SessionIdTooLong,
        error.InvalidSessionId,
        error.BufferTooSmall,
        => .decode,
        else => .other,
    };
}

/// Renders the registry under the worker prefix, as the scrape callback
/// expects.
pub fn render(registry: *const Metrics, writer: std.io.AnyWriter) anyerror!void {
    try obs.metrics.render("fpkg_worker_", registry, writer);
}
