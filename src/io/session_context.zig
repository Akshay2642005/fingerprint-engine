//! `signal_package_context` payload codec (ADR-013 §4, story m7-session-id).
//!
//! The ingress learns two things the worker cannot derive: the browser/idp
//! session id from the `x-fpkg-session-id` request header, and when the
//! package actually arrived. Neither fits in the FPKG frame header —
//! `reserved` is pinned to zero (R-5) — and the signal package body belongs to
//! the client (it is integrity-checked and hashed verbatim), so it cannot be
//! annotated either. The ingress therefore *wraps* the body:
//!
//!     payload = [u16 session_len (LE)][session_id]
//!               [i64 ingress_received_at (LE, epoch ms)]
//!               [signal_package body]
//!
//! carried in a `signal_package_context` frame. `session_len` may be 0: the
//! session header is optional, but the ingress timestamp is not, because every
//! HTTP collection traversed the ingress. Direct frame clients (TCP,
//! loopback) keep sending a plain `signal_package`, where the envelope records
//! `ingress_received_at = 0` — the ADR's "did not traverse the ingress" case.
//!
//! The worker strips the header and hands the inner body to the engine
//! unchanged, so the canonical digest is identical with and without a context.
//!
//! This module is the single implementation both sides share: the ingress
//! validates and wraps, the worker validates and unwraps. Pure std — no io,
//! adapter, or engine dependency.

const std = @import("std");

/// Upper bound on an accepted session id. Long enough for a UUID, an opaque
/// IdP handle, or a namespaced `tenant:session` pair; short enough that the
/// wrapped frame stays far below any transport limit.
pub const max_session_id_len: usize = 128;

/// Bytes of the session-length field that opens the context header.
pub const length_prefix_len: usize = 2;

/// Bytes of the ingress arrival timestamp.
pub const timestamp_len: usize = 8;

/// Bytes the context header adds to a package body, excluding the session id
/// itself: the length field plus the timestamp.
pub const header_len: usize = length_prefix_len + timestamp_len;

pub const Error = error{
    SessionIdTooLong,
    InvalidSessionId,
    /// The payload ends before the declared session id does.
    Truncated,
    /// `out` cannot hold the wrapped payload.
    BufferTooSmall,
};

/// True when `session` is a well-formed *present* session id: 1..
/// `max_session_id_len` bytes of `[A-Za-z0-9._:-]`. Those are safe to log, safe
/// to place in JSON without escaping, and cover UUIDs, `tenant:session`
/// namespace pairs, and the common identity-provider handle formats. Anything
/// needing escaping (whitespace, quotes, control bytes, non-ASCII) is rejected
/// at the boundary rather than stored in the ledger.
///
/// Absence is expressed by an empty slice, which this predicate rejects; the
/// ingress treats a present-but-empty header as malformed.
pub fn isValidSessionId(session: []const u8) bool {
    if (session.len == 0 or session.len > max_session_id_len) return false;
    return hasValidChars(session);
}

fn hasValidChars(session: []const u8) bool {
    for (session) |byte| {
        if (std.ascii.isAlphanumeric(byte)) continue;
        switch (byte) {
            '.', '_', ':', '-' => continue,
            else => return false,
        }
    }
    return true;
}

/// Wraps `body` behind the ingress context into `out` and returns the written
/// slice. `out.len` must be at least `header_len + session_id.len + body.len`.
/// `session_id` may be empty (no session header was sent); when non-empty it
/// must satisfy `isValidSessionId`.
pub fn wrap(
    out: []u8,
    session_id: []const u8,
    ingress_received_at: i64,
    body: []const u8,
) Error![]const u8 {
    if (session_id.len > max_session_id_len) return error.SessionIdTooLong;
    if (session_id.len > 0 and !hasValidChars(session_id)) return error.InvalidSessionId;

    const total = header_len + session_id.len + body.len;
    if (out.len < total) return error.BufferTooSmall;

    // Little-endian, like every other FPKG field.
    out[0] = @intCast(session_id.len & 0xff);
    out[1] = @intCast(session_id.len >> 8);

    var pos: usize = length_prefix_len;
    if (session_id.len > 0) {
        @memcpy(out[pos .. pos + session_id.len], session_id);
        pos += session_id.len;
    }

    const stamp: u64 = @bitCast(ingress_received_at);
    for (0..timestamp_len) |i| {
        out[pos + i] = @truncate(stamp >> @intCast(8 * i));
    }
    pos += timestamp_len;

    @memcpy(out[pos..total], body);
    return out[0..total];
}

pub const View = struct {
    /// The session id, borrowing from the payload; empty when none was sent.
    session_id: []const u8,
    /// Ingress arrival time in epoch milliseconds; 0 when the collection did
    /// not traverse the ingress.
    ingress_received_at: i64,
    /// The signal package body, unchanged — this is exactly what the engine
    /// hashes, so wrapping must not alter a single byte of it.
    body: []const u8,
};

/// Splits a `signal_package_context` payload into its session id, ingress
/// arrival time, and package body. The whole remainder is the body (its length
/// is implicit), so a truncated context header is the only framing failure.
pub fn unwrap(payload: []const u8) Error!View {
    if (payload.len < length_prefix_len) return error.Truncated;

    const session_len = @as(usize, payload[0]) | (@as(usize, payload[1]) << 8);
    if (session_len > max_session_id_len) return error.SessionIdTooLong;
    if (payload.len < header_len + session_len) return error.Truncated;

    const session_id = payload[length_prefix_len .. length_prefix_len + session_len];
    if (session_id.len > 0 and !hasValidChars(session_id)) return error.InvalidSessionId;

    const stamp_at = length_prefix_len + session_len;
    var stamp: u64 = 0;
    for (0..timestamp_len) |i| {
        stamp |= @as(u64, payload[stamp_at + i]) << @intCast(8 * i);
    }

    return .{
        .session_id = session_id,
        .ingress_received_at = @bitCast(stamp),
        .body = payload[header_len + session_len ..],
    };
}
