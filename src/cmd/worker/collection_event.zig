//! Builds the per-collection event envelope the worker publishes alongside
//! every successful digest reply (ADR-013 §1, story m7-collection-event-publish).
//!
//! The in-band `fingerprint_result` reply is unchanged: it is still the
//! browser/server contract and still carries a status byte. This module turns
//! the *same* already-received package into one extra outbound frame:
//!
//!   signal_package(_context) ──► engine reply (unchanged)
//!                            └─► collection_event (JSON, ADR-013 §2)
//!
//! Everything here is a pure function of the request and the reply — no clock,
//! no cross-user state — so the envelope is as deterministic as the digest it
//! describes. The values are recomputed from the package rather than scraped
//! back out of the reply: the decoder is the same one the engine used, and the
//! canonical order is the engine's, which is what the ledger needs to query.
//!
//! A collection that did not succeed produces no envelope: a failed reply has
//! no trustworthy digests to publish, and the engine's status is already
//! visible on the reply channel. The caller treats a `null` result as "nothing
//! to publish", not an error.

const std = @import("std");
const core = @import("core");
const serialization = @import("serialization");
const engine = @import("engine");
const adapter = @import("adapter");
const io = @import("io");

/// Upper bound on the encoded JSON payload (64 KiB, matching the reply cap).
/// A package with unusually many/large feature values can exceed it; the
/// caller logs the drop rather than truncating the document — a truncated
/// envelope would be a corrupt ledger row, which is worse than a missing one
/// (the platform can still fall back to the live `result.*` fanout).
pub const max_payload: usize = 64 * 1024;

/// Context extracted from an inbound frame. A plain `signal_package` has no
/// session id and did not traverse the ingress, so `ingress_received_at = 0`
/// (ADR-013 §2).
const Context = struct {
    body: []const u8,
    session_id: []const u8 = "",
    ingress_received_at: i64 = 0,
};

const HashResult = struct {
    fingerprint_digest: [32]u8,
    feature_count: u16,
    schema_version: u16,
    core_digest: [32]u8,
    core_feature_count: u16,
    core_version: u16,
};

/// Builds one `collection_event` frame from the inbound frame and the worker's
/// reply. Returns `null` when the pair is not a successful collection (the
/// caller then publishes nothing). `out` must hold at least
/// `io.frame.header_size + max_payload` bytes.
pub fn build(
    frame: []const u8,
    reply_frame: []const u8,
    allocator: std.mem.Allocator,
    out: []u8,
) !?[]const u8 {
    if (out.len < io.frame.header_size) return error.BufferTooSmall;

    const context = try contextOf(frame) orelse return null;

    const reply = try adapter.decodeFrame(reply_frame);
    if (reply.header.message_type != .fingerprint_result) return null;
    if (reply.payload.len < 1) return null;
    const status = std.meta.intToEnum(engine.Status, reply.payload[0]) catch return null;
    if (status != .ok) return null;

    const result = try parseResult(reply.payload[1..]) orelse return null;

    var fp = try engine.format.decodePayload(context.body, allocator);
    engine.format.canonicalize(&fp);

    const assessment = try core.risk.computeRisk(fp, allocator);
    defer allocator.free(assessment.flags);

    const event = serialization.CollectionEvent{
        .schema_version = result.schema_version,
        .package_id = fp.metadata.package_id,
        .session_id = context.session_id,
        .fingerprint_digest = result.fingerprint_digest,
        .core_digest = result.core_digest,
        .core_version = result.core_version,
        .feature_count = result.feature_count,
        .core_feature_count = result.core_feature_count,
        .status = status.code(),
        .entropy = core.entropy.fingerprintEntropy(fp),
        .risk = .{
            .score = assessment.score,
            .label = assessment.label,
            .flags = assessment.flags,
        },
        .collected_at = fp.metadata.collected_at,
        .ingress_received_at = context.ingress_received_at,
        .sdk_version = fp.metadata.sdk_version,
        .signals = fp.features,
    };

    const payload = encode(event, out[io.frame.header_size..]) catch |err| switch (err) {
        error.NoSpaceLeft => return error.EventTooLarge,
        else => |e| return e,
    };

    // The payload now lives at out[header_size..]; writing the header in place
    // keeps the frame zero-copy (buildFrame would copy the payload onto itself).
    const header = io.frame.FrameHeader{
        .message_type = .collection_event,
        .codec = .json,
        .payload_len = @intCast(payload.len),
        .integrity = io.frame.FrameHeader.integrityOf(payload),
    };
    var w = io.Writer.init(out);
    try header.encode(&w);
    return out[0 .. io.frame.header_size + payload.len];
}

/// Reads the inbound context without handing the engine anything but the
/// package body. A malformed context is a protocol error, as in the worker.
fn contextOf(frame: []const u8) !?Context {
    const decoded = try adapter.decodeFrame(frame);
    switch (decoded.header.message_type) {
        .signal_package => return .{ .body = decoded.payload },
        .signal_package_context => {
            const view = try io.session_context.unwrap(decoded.payload);
            return .{
                .body = view.body,
                .session_id = view.session_id,
                .ingress_received_at = view.ingress_received_at,
            };
        },
        else => return null,
    }
}

/// Parses the v2 `fingerprint_result` payload. The v1 prefix alone is not
/// enough: the envelope needs the appended core digest triple (ADR-013 §3).
fn parseResult(payload: []const u8) !?HashResult {
    const Layout = engine.ops.hash.Layout;
    if (payload.len < Layout.len) return null;

    var result: HashResult = undefined;
    @memcpy(
        &result.fingerprint_digest,
        payload[Layout.fingerprint_digest.offset..][0..Layout.fingerprint_digest.len],
    );
    result.feature_count = readU16(payload, Layout.feature_count);
    result.schema_version = readU16(payload, Layout.schema_version);
    @memcpy(
        &result.core_digest,
        payload[Layout.core_digest.offset..][0..Layout.core_digest.len],
    );
    result.core_feature_count = readU16(payload, Layout.core_feature_count);
    result.core_version = readU16(payload, Layout.core_version);
    return result;
}

fn readU16(payload: []const u8, field: engine.ops.hash.Layout.Field) u16 {
    const at = field.offset;
    return @as(u16, payload[at]) | (@as(u16, payload[at + 1]) << 8);
}

fn encode(event: serialization.CollectionEvent, out: []u8) ![]const u8 {
    var fbs = std.io.fixedBufferStream(out);
    try serialization.encodeCollectionEvent(fbs.writer(), event);
    return fbs.getWritten();
}
