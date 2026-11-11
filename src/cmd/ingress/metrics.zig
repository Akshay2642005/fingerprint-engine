//! Ingress metric registry (ADR-014 §2, story m8-observability).
//!
//! The catalog lives in `specs/architecture/observability.md` §Ingress. This
//! file is only the declaration; `obs.metrics` owns the storage and the
//! exposition, and `obs.scrape` serves it on `--metrics-listen`.
//!
//! `fpkg_ingress_build_info` and `fpkg_ingress_ready` are **not** fields here:
//! the scrape listener emits both from its own preamble, and declaring them in
//! the registry too would emit duplicate `# TYPE` lines.
//!
const std = @import("std");
const obs = @import("obs");

/// HTTP response class; the label values are the catalog's (`2xx`/`4xx`/`5xx`).
pub const StatusClass = enum { @"2xx", @"4xx", @"5xx" };

/// Why a request was refused before it reached a worker. Values are fixed
/// categories, never the error name, so cardinality stays clamped even if a
/// new error is added.
pub const AuthReason = enum { missing, malformed, forged, stale, replayed, cache_full };
pub const RequestIdSource = enum { minted, honoured };

/// Request latency buckets in seconds (observability.md §Ingress). HTTP-in to
/// reply-out covers the worker round trip, which is the number an SLO cares
/// about.
pub const duration_buckets = [_]f64{
    0.001, 0.0025, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5,
};

/// The ingress registry. One instance per process; the scrape thread reads it
/// while the accept thread writes, which is why every field is atomic.
pub const Metrics = struct {
    requests_total: obs.metrics.CounterLabeled(struct { status: StatusClass }) = .{},
    request_duration_seconds: obs.metrics.Histogram(&duration_buckets) = .{},
    auth_rejections_total: obs.metrics.CounterLabeled(struct { reason: AuthReason }) = .{},
    replay_cache_entries: obs.metrics.Gauge() = .{},
    replay_cache_capacity: obs.metrics.Gauge() = .{},
    worker_pool_healthy: obs.metrics.Gauge() = .{},
    request_id_total: obs.metrics.CounterLabeled(struct { source: RequestIdSource }) = .{},
};

/// Renders the registry under the ingress prefix, as the scrape callback
/// expects.
pub fn render(registry: *const Metrics, writer: std.io.AnyWriter) anyerror!void {
    try obs.metrics.render("fpkg_ingress_", registry, writer);
}
