//! Zero-dependency, comptime-declared metrics registry (ADR-014, story
//! m8-observability).
//!
//! A metric set is a plain struct whose fields are the metric types below.
//! Nothing is registered at runtime, nothing allocates, and every label value
//! is a compile-time enum — cardinality is bounded by the type system, so
//! there is no label map to grow and no unbounded series to leak ids into.
//!
//!     const Ingress = struct {
//!         requests_total: obs.CounterLabeled(StatusClass) = .{},
//!         request_duration_seconds: obs.Histogram(&duration_buckets) = .{},
//!         replay_cache_entries: obs.Gauge() = .{},
//!     };
//!
//! Storage is atomic (`std.atomic.Value`) because a scrape listener reads it
//! from its own thread while request threads increment (ADR-014 §3). The
//! hot-path cost of a counter is one atomic add; percentiles are not stored —
//! the exposition carries cumulative histogram buckets and the scraper derives
//! `p50`/`p95`/`p99` with `histogram_quantile`.
//!
//! Naming is the caller's job: `render("fpkg_ingress_", &metrics, writer)`
//! emits `fpkg_ingress_requests_total`, etc. Prometheus text format 0.0.4.

const std = @import("std");

/// Metric family kind, used by `render` to choose the exposition shape.
pub const Kind = enum { counter, gauge, histogram };

/// The empty label set. Unlabeled metrics use it so every metric exposes the
/// same `label_info` and rendering has one code path.
pub const NoLabels = struct {};

/// Content type of `render`'s output (Prometheus text format 0.0.4).
pub const exposition_content_type = "text/plain; version=0.0.4; charset=utf-8";

/// Histogram bucket bounds must be finite and strictly ascending; the `+Inf`
/// bucket is implicit. A violation is a compile error, not a runtime surprise.
fn validateBounds(comptime bounds: []const f64) void {
    comptime {
        if (bounds.len == 0) @compileError("histogram requires at least one bucket bound");
        var i: usize = 0;
        while (i < bounds.len) : (i += 1) {
            if (!std.math.isFinite(bounds[i])) {
                @compileError("histogram bounds must be finite; the +Inf bucket is implicit");
            }
            if (i > 0 and !(bounds[i] > bounds[i - 1])) {
                @compileError("histogram bounds must be strictly ascending");
            }
        }
    }
}

/// Zero-initialized array of atomics. Field initializers run at comptime, so
/// this is a compile-time constant with no runtime work.
fn zeroedAtomics(comptime T: type, comptime n: usize) [n]std.atomic.Value(T) {
    var out: [n]std.atomic.Value(T) = undefined;
    for (&out) |*slot| slot.* = .{ .raw = 0 };
    return out;
}

/// Zero-initialized `rows × cols` matrix of atomics (labeled histograms).
fn zeroedAtomicMatrix(
    comptime T: type,
    comptime rows: usize,
    comptime cols: usize,
) [rows][cols]std.atomic.Value(T) {
    var out: [rows][cols]std.atomic.Value(T) = undefined;
    for (&out) |*row| {
        for (row) |*slot| slot.* = .{ .raw = 0 };
    }
    return out;
}

/// `n` copies of a comptime value, usable as a field initializer.
fn repeated(comptime T: type, comptime value: T, comptime n: usize) [n]T {
    var out: [n]T = undefined;
    for (&out) |*slot| slot.* = value;
    return out;
}

/// A float stored in an atomic integer: histograms need a sum, and there is no
/// atomic float. Addition is a CAS loop; contention is negligible (many
/// observers, one scraper) and the alternative — a lock — is worse.
const AtomicF64 = struct {
    raw: std.atomic.Value(u64) = .{ .raw = 0 },

    fn load(self: *const AtomicF64) f64 {
        return @bitCast(self.raw.load(.monotonic));
    }

    fn add(self: *AtomicF64, value: f64) void {
        var current = self.raw.load(.monotonic);
        while (true) {
            const sum = @as(f64, @bitCast(current)) + value;
            const next: u64 = @bitCast(sum);
            current = self.raw.cmpxchgWeak(current, next, .monotonic, .monotonic) orelse return;
        }
    }
};

/// Compile-time label metadata for a label struct.
///
/// A label struct has one field per label name, and each field type is an
/// enum whose tags are the allowed values. The set of series is the cartesian
/// product, laid out with row-major strides so `index()` is a few integer
/// multiplies — no hashing, no allocation, no map.
pub fn LabelInfo(comptime Labels: type) type {
    if (@typeInfo(Labels) != .@"struct") {
        @compileError("metric labels must be a struct whose fields are enums");
    }
    const fields = std.meta.fields(Labels);
    const meta = comptime blk: {
        var count: usize = 1;
        var strides: [fields.len]usize = undefined;
        var i: usize = fields.len;
        while (i > 0) {
            i -= 1;
            const FieldType = fields[i].type;
            if (@typeInfo(FieldType) != .@"enum") {
                @compileError("metric label field '" ++ fields[i].name ++ "' must be an enum");
            }
            strides[i] = count;
            count *= @typeInfo(FieldType).@"enum".fields.len;
        }
        break :blk .{ .count = count, .strides = strides };
    };

    return struct {
        /// Total number of series in this label set.
        pub const count: usize = meta.count;
        /// Row-major stride of each label field within `count`.
        pub const strides: [fields.len]usize = meta.strides;

        /// Series index for a concrete label value.
        pub fn index(labels: Labels) usize {
            var idx: usize = 0;
            inline for (fields, 0..) |field, i| {
                idx += @as(usize, @intFromEnum(@field(labels, field.name))) * strides[i];
            }
            return idx;
        }

        /// Label value of a series; the inverse of `index`, used by `render`.
        pub fn labelsAt(comptime series: usize) Labels {
            var out: Labels = undefined;
            inline for (fields, 0..) |field, i| {
                const options = std.meta.fields(field.type).len;
                const value = (series / strides[i]) % options;
                @field(out, field.name) = @as(field.type, @enumFromInt(value));
            }
            return out;
        }
    };
}

/// Monotonic counter without labels: `inc()`, `add(n)`.
pub fn Counter() type {
    return struct {
        pub const metric_kind: Kind = .counter;
        pub const labels: type = NoLabels;
        pub const label_info = LabelInfo(NoLabels);

        raw: std.atomic.Value(u64) = .{ .raw = 0 },

        pub fn inc(self: *@This()) void {
            _ = self.raw.fetchAdd(1, .monotonic);
        }

        pub fn add(self: *@This(), n: u64) void {
            if (n == 0) return;
            _ = self.raw.fetchAdd(n, .monotonic);
        }

        pub fn get(self: *const @This()) u64 {
            return self.raw.load(.monotonic);
        }

        /// Series accessor used by `render`; an unlabeled metric has one series.
        pub fn getAt(self: *const @This(), series: usize) u64 {
            std.debug.assert(series == 0);
            return self.get();
        }
    };
}

/// Monotonic counter with a comptime label set: `inc(labels)`, `add(labels, n)`.
pub fn CounterLabeled(comptime Labels: type) type {
    const info = LabelInfo(Labels);
    return struct {
        pub const metric_kind: Kind = .counter;
        pub const labels: type = Labels;
        pub const label_info = info;

        raw: [info.count]std.atomic.Value(u64) = zeroedAtomics(u64, info.count),

        pub fn inc(self: *@This(), label_values: Labels) void {
            _ = self.raw[info.index(label_values)].fetchAdd(1, .monotonic);
        }

        pub fn add(self: *@This(), label_values: Labels, n: u64) void {
            if (n == 0) return;
            _ = self.raw[info.index(label_values)].fetchAdd(n, .monotonic);
        }

        pub fn get(self: *const @This(), label_values: Labels) u64 {
            return self.raw[info.index(label_values)].load(.monotonic);
        }

        pub fn getAt(self: *const @This(), series: usize) u64 {
            std.debug.assert(series < info.count);
            return self.raw[series].load(.monotonic);
        }
    };
}

/// Gauge without labels: `set(v)`, `inc()`, `dec()`, `add(v)`.
pub fn Gauge() type {
    return struct {
        pub const metric_kind: Kind = .gauge;
        pub const labels: type = NoLabels;
        pub const label_info = LabelInfo(NoLabels);

        raw: std.atomic.Value(i64) = .{ .raw = 0 },

        pub fn set(self: *@This(), value: i64) void {
            self.raw.store(value, .monotonic);
        }

        pub fn inc(self: *@This()) void {
            _ = self.raw.fetchAdd(1, .monotonic);
        }

        pub fn dec(self: *@This()) void {
            _ = self.raw.fetchSub(1, .monotonic);
        }

        pub fn add(self: *@This(), n: i64) void {
            if (n == 0) return;
            _ = self.raw.fetchAdd(n, .monotonic);
        }

        pub fn get(self: *const @This()) i64 {
            return self.raw.load(.monotonic);
        }

        pub fn getAt(self: *const @This(), series: usize) i64 {
            std.debug.assert(series == 0);
            return self.get();
        }
    };
}

/// Gauge with a comptime label set.
pub fn GaugeLabeled(comptime Labels: type) type {
    const info = LabelInfo(Labels);
    return struct {
        pub const metric_kind: Kind = .gauge;
        pub const labels: type = Labels;
        pub const label_info = info;

        raw: [info.count]std.atomic.Value(i64) = zeroedAtomics(i64, info.count),

        pub fn set(self: *@This(), label_values: Labels, value: i64) void {
            self.raw[info.index(label_values)].store(value, .monotonic);
        }

        pub fn inc(self: *@This(), label_values: Labels) void {
            _ = self.raw[info.index(label_values)].fetchAdd(1, .monotonic);
        }

        pub fn dec(self: *@This(), label_values: Labels) void {
            _ = self.raw[info.index(label_values)].fetchSub(1, .monotonic);
        }

        pub fn add(self: *@This(), label_values: Labels, n: i64) void {
            if (n == 0) return;
            _ = self.raw[info.index(label_values)].fetchAdd(n, .monotonic);
        }

        pub fn get(self: *const @This(), label_values: Labels) i64 {
            return self.raw[info.index(label_values)].load(.monotonic);
        }

        pub fn getAt(self: *const @This(), series: usize) i64 {
            std.debug.assert(series < info.count);
            return self.raw[series].load(.monotonic);
        }
    };
}

/// Fixed-bucket histogram without labels. `bounds` are upper bounds (`le`);
/// an implicit `+Inf` bucket catches everything above the last bound.
pub fn Histogram(comptime bounds: []const f64) type {
    validateBounds(bounds);
    const bucket_count = bounds.len;
    const bound_values: [bucket_count]f64 = bounds[0..bucket_count].*;

    return struct {
        pub const metric_kind: Kind = .histogram;
        pub const labels: type = NoLabels;
        pub const label_info = LabelInfo(NoLabels);
        pub const upper_bounds: [bucket_count]f64 = bound_values;

        buckets: [bucket_count + 1]std.atomic.Value(u64) =
            zeroedAtomics(u64, bucket_count + 1),
        sum: AtomicF64 = .{},
        count: std.atomic.Value(u64) = .{ .raw = 0 },

        pub fn observe(self: *@This(), value: f64) void {
            _ = self.count.fetchAdd(1, .monotonic);
            self.sum.add(value);
            _ = self.buckets[bucketIndex(value)].fetchAdd(1, .monotonic);
        }

        fn bucketIndex(value: f64) usize {
            for (bound_values, 0..) |bound, i| {
                if (value <= bound) return i;
            }
            return bucket_count;
        }

        pub fn bucketAt(self: *const @This(), series: usize, bucket: usize) u64 {
            std.debug.assert(series == 0);
            std.debug.assert(bucket <= bucket_count);
            return self.buckets[bucket].load(.monotonic);
        }

        pub fn sumAt(self: *const @This(), series: usize) f64 {
            std.debug.assert(series == 0);
            return self.sum.load();
        }

        pub fn countAt(self: *const @This(), series: usize) u64 {
            std.debug.assert(series == 0);
            return self.count.load(.monotonic);
        }
    };
}

/// Fixed-bucket histogram with a comptime label set.
pub fn HistogramLabeled(comptime Labels: type, comptime bounds: []const f64) type {
    const info = LabelInfo(Labels);
    validateBounds(bounds);
    const bucket_count = bounds.len;
    const bound_values: [bucket_count]f64 = bounds[0..bucket_count].*;

    return struct {
        pub const metric_kind: Kind = .histogram;
        pub const labels: type = Labels;
        pub const label_info = info;
        pub const upper_bounds: [bucket_count]f64 = bound_values;

        buckets: [info.count][bucket_count + 1]std.atomic.Value(u64) =
            zeroedAtomicMatrix(u64, info.count, bucket_count + 1),
        sums: [info.count]AtomicF64 = repeated(AtomicF64, .{}, info.count),
        counts: [info.count]std.atomic.Value(u64) = zeroedAtomics(u64, info.count),

        pub fn observe(self: *@This(), label_values: Labels, value: f64) void {
            const series = info.index(label_values);
            _ = self.counts[series].fetchAdd(1, .monotonic);
            self.sums[series].add(value);
            _ = self.buckets[series][bucketIndex(value)].fetchAdd(1, .monotonic);
        }

        fn bucketIndex(value: f64) usize {
            for (bound_values, 0..) |bound, i| {
                if (value <= bound) return i;
            }
            return bucket_count;
        }

        pub fn bucketAt(self: *const @This(), series: usize, bucket: usize) u64 {
            std.debug.assert(series < info.count);
            std.debug.assert(bucket <= bucket_count);
            return self.buckets[series][bucket].load(.monotonic);
        }

        pub fn sumAt(self: *const @This(), series: usize) f64 {
            std.debug.assert(series < info.count);
            return self.sums[series].load();
        }

        pub fn countAt(self: *const @This(), series: usize) u64 {
            std.debug.assert(series < info.count);
            return self.counts[series].load(.monotonic);
        }
    };
}

/// Optional `le` label on a histogram bucket line.
const LeKind = union(enum) {
    none,
    bound: f64,
    inf,
};

fn writeEscaped(writer: anytype, value: []const u8) !void {
    for (value) |c| switch (c) {
        '\\' => try writer.writeAll("\\\\"),
        '"' => try writer.writeAll("\\\""),
        '\n' => try writer.writeAll("\\n"),
        else => try writer.writeByte(c),
    };
}

/// Writes `{status="2xx",le="0.01"}` (or nothing when there are no labels and
/// no `le`). Enum tags cannot contain quotes or newlines, but values are
/// escaped anyway so the renderer does not depend on that invariant.
fn writeLabels(writer: anytype, comptime Labels: type, label_values: Labels, comptime le: LeKind) !void {
    const fields = std.meta.fields(Labels);
    const has_le = comptime switch (le) {
        .none => false,
        else => true,
    };
    if (comptime fields.len == 0 and !has_le) return;

    try writer.writeByte('{');
    var first = true;
    inline for (fields) |field| {
        if (!first) try writer.writeByte(',');
        first = false;
        try writer.print("{s}=\"", .{field.name});
        try writeEscaped(writer, @tagName(@field(label_values, field.name)));
        try writer.writeByte('"');
    }
    switch (le) {
        .none => {},
        .bound => |bound| {
            if (!first) try writer.writeByte(',');
            try writer.print("le=\"{d}\"", .{bound});
        },
        .inf => {
            if (!first) try writer.writeByte(',');
            try writer.writeAll("le=\"+Inf\"");
        },
    }
    try writer.writeByte('}');
}

fn renderOne(
    comptime prefix: []const u8,
    comptime name: []const u8,
    metric: anytype,
    writer: anytype,
) !void {
    const Metric = @TypeOf(metric.*);
    const info = Metric.label_info;
    const full = comptime prefix ++ name;

    switch (Metric.metric_kind) {
        .counter => {
            try writer.print("# TYPE {s} counter\n", .{full});
            inline for (0..info.count) |series| {
                try writer.print("{s}", .{full});
                try writeLabels(writer, Metric.labels, info.labelsAt(series), .none);
                try writer.print(" {d}\n", .{metric.getAt(series)});
            }
        },
        .gauge => {
            try writer.print("# TYPE {s} gauge\n", .{full});
            inline for (0..info.count) |series| {
                try writer.print("{s}", .{full});
                try writeLabels(writer, Metric.labels, info.labelsAt(series), .none);
                try writer.print(" {d}\n", .{metric.getAt(series)});
            }
        },
        .histogram => {
            try writer.print("# TYPE {s} histogram\n", .{full});
            inline for (0..info.count) |series| {
                const label_values = info.labelsAt(series);
                var cumulative: u64 = 0;
                inline for (Metric.upper_bounds, 0..) |bound, bucket| {
                    cumulative += metric.bucketAt(series, bucket);
                    try writer.print("{s}_bucket", .{full});
                    try writeLabels(writer, Metric.labels, label_values, .{ .bound = bound });
                    try writer.print(" {d}\n", .{cumulative});
                }
                // `+Inf` is the count of every observation above the last bound.
                try writer.print("{s}_bucket", .{full});
                try writeLabels(writer, Metric.labels, label_values, .inf);
                try writer.print(" {d}\n", .{metric.bucketAt(series, Metric.upper_bounds.len)});
                try writer.print("{s}_sum", .{full});
                try writeLabels(writer, Metric.labels, label_values, .none);
                try writer.print(" {d}\n", .{metric.sumAt(series)});
                try writer.print("{s}_count", .{full});
                try writeLabels(writer, Metric.labels, label_values, .none);
                try writer.print(" {d}\n", .{metric.countAt(series)});
            }
        },
    }
}

/// True when `T` is one of the metric struct types above. `@hasDecl` is only
/// valid for types that can hold declarations, so inspect the type first.
fn isMetricType(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct", .@"enum", .@"union", .@"opaque" => @hasDecl(T, "metric_kind"),
        else => false,
    };
}

/// Renders a registry as Prometheus text format. `registry` must be a pointer
/// to a struct; metric fields are detected by their `metric_kind` declaration,
/// and any non-metric field is skipped.
///
///     var buf: [64 * 1024]u8 = undefined;
///     var stream = std.io.fixedBufferStream(&buf);
///     try obs.metrics.render("fpkg_ingress_", &metrics, stream.writer());
pub fn render(comptime prefix: []const u8, registry: anytype, writer: anytype) !void {
    const Registry = @TypeOf(registry.*);
    inline for (std.meta.fields(Registry)) |field| {
        if (comptime isMetricType(field.type)) {
            try renderOne(prefix, field.name, &@field(registry.*, field.name), writer);
        }
    }
}
