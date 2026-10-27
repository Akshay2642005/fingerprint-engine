const std = @import("std");
const model = @import("model");
const core = @import("core");
const json = @import("json.zig");

/// Risk summary embedded in a collection event. Mirrors the fields of
/// `core.risk.RiskAssessment` that the ledger stores; the engine's risk op
/// also carries `feature_count`/`total_defined`, which are already represented
/// by the envelope's counts.
pub const RiskSummary = struct {
    score: f64,
    label: []const u8,
    flags: []const core.risk.RiskFlag,
};

/// One per-collection event (ADR-013 §2 / `06-event-envelope-schema.md`).
///
/// This is the single durable document the platform ledger stores: the
/// canonical signals, both digests, and the computed scores, so it never has to
/// re-join the live `result.*` fanout.
pub const CollectionEvent = struct {
    /// Signal schema revision (`fingerprint.metadata.schema_version`).
    schema_version: u16,
    /// SDK-minted per-collection id (128-bit). Also the ledger's idempotency
    /// key — retries collide on it instead of duplicating rows.
    package_id: [16]u8,
    /// `x-fpkg-session-id`, or empty when the client did not send one.
    session_id: []const u8,
    /// v2 `fingerprint_digest` (full feature set).
    fingerprint_digest: [32]u8,
    /// Stable-core digest (`core.hashing.hashCoreFingerprintBuffer`).
    core_digest: [32]u8,
    /// Revision of the stable-core subset that produced `core_digest`.
    core_version: u16,
    feature_count: u16,
    core_feature_count: u16,
    /// Engine status of the collection (0 = ok).
    status: u8,
    entropy: f64,
    risk: RiskSummary,
    collected_at: i64,
    /// When the ingress accepted the package. 0 when the collection did not
    /// traverse the ingress (e.g. loopback/TCP).
    ingress_received_at: i64,
    sdk_version: []const u8,
    /// Canonicalized features: MUST be sorted by FeatureID (the caller runs
    /// `engine.format.canonicalize`). The encoder never allocates or reorders.
    signals: []const model.Feature,
};

/// Encodes a collection event as deterministic JSON in the fixed key order
/// ADR-013 §2 freezes. Digests are lower-hex; signal keys are registry names.
///
/// Determinism: same input → same bytes on every platform. There is no
/// whitespace ambiguity (2-space indent, one field per line) and no floating
/// point formatting variance (`std.fmt` is locale-free).
// story: m7-collection-event
pub fn encodeCollectionEvent(w: anytype, event: CollectionEvent) !void {
    try w.writeAll("{\n");

    try w.print("  \"schema_version\": {},\n", .{event.schema_version});
    try w.writeAll("  \"package_id\": \"");
    try writeHex(w, &event.package_id);
    try w.writeAll("\",\n");

    try w.writeAll("  \"session_id\": ");
    try json.writeJsonString(w, event.session_id);
    try w.writeAll(",\n");

    try w.writeAll("  \"fingerprint_id\": \"");
    try writeHex(w, &event.fingerprint_digest);
    try w.writeAll("\",\n");

    try w.writeAll("  \"core_digest\": \"");
    try writeHex(w, &event.core_digest);
    try w.writeAll("\",\n");

    try w.print("  \"core_version\": {},\n", .{event.core_version});
    try w.print("  \"feature_count\": {},\n", .{event.feature_count});
    try w.print("  \"core_feature_count\": {},\n", .{event.core_feature_count});
    try w.print("  \"status\": {},\n", .{event.status});

    try w.print("  \"entropy\": {d},\n", .{event.entropy});

    try w.writeAll("  \"risk\": {\n");
    try w.print("    \"score\": {d},\n", .{event.risk.score});
    try w.writeAll("    \"label\": ");
    try json.writeJsonString(w, event.risk.label);
    try w.writeAll(",\n");
    try w.writeAll("    \"flags\": [");
    for (event.risk.flags, 0..) |flag, i| {
        if (i > 0) try w.writeAll(", ");
        try json.writeJsonString(w, @tagName(flag));
    }
    try w.writeAll("]\n  },\n");

    try w.print("  \"collected_at\": {},\n", .{event.collected_at});
    try w.print("  \"ingress_received_at\": {},\n", .{event.ingress_received_at});

    try w.writeAll("  \"sdk_version\": ");
    try json.writeJsonString(w, event.sdk_version);
    try w.writeAll(",\n");

    try w.writeAll("  \"signals\": {\n");
    for (event.signals, 0..) |feature, i| {
        if (i > 0) try w.writeAll(",\n");
        try w.writeAll("    ");
        try json.writeJsonString(w, model.Registry.get(feature.id).name);
        try w.writeAll(": ");
        try json.writeJsonValue(w, feature.value);
    }
    if (event.signals.len > 0) try w.writeAll("\n");
    try w.writeAll("  }\n");

    try w.writeAll("}");
}

fn writeHex(w: anytype, bytes: []const u8) !void {
    for (bytes) |byte| try w.print("{x:0>2}", .{byte});
}
