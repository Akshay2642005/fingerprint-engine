// story: m7-session-id
//! `signal_package_context` payload codec (ADR-013 §4): the ingress context —
//! optional session id plus arrival timestamp — that the ingress wraps around
//! a client's signal package. These tests pin the exact framing, the
//! accept/reject boundary of the charset, and — most importantly — that the
//! inner body survives byte-for-byte, because that body is what the engine
//! hashes.

const std = @import("std");
const testing = std.testing;
const io = @import("io");

const ctx = io.session_context;

test "session context: accepts UUIDs, namespaced ids, and dotted/underscored handles" {
    const accepted = [_][]const u8{
        "s",
        "sess-1",
        "8d56529f-0604-0b90-df4c-b25a3811a10e",
        "tenant42:abc_DEF.123",
        "::1",
        "....",
    };
    for (accepted) |session| {
        try testing.expect(ctx.isValidSessionId(session));
    }
}

test "session context: accepts exactly the maximum length and rejects one more" {
    const max_buf = [_]u8{'a'} ** ctx.max_session_id_len;
    try testing.expect(ctx.isValidSessionId(&max_buf));

    const too_long = [_]u8{'a'} ** (ctx.max_session_id_len + 1);
    try testing.expect(!ctx.isValidSessionId(&too_long));
}

test "session context: rejects empty, whitespace, separators, and non-ASCII ids" {
    const rejected = [_][]const u8{
        "",
        "session id", // space
        "session\tid",
        "session\nid",
        "session/id", // path separator encourages log injection
        "session,id",
        "session+id",
        "session@id",
        "session\"id", // would need JSON escaping
        "session\\id",
        "s\xc3\xa9ssion", // non-ASCII bytes
        "sess\x00ion", // NUL
    };
    for (rejected) |session| {
        try testing.expect(!ctx.isValidSessionId(session));
    }
}

test "session context: wrap writes length, session, little-endian timestamp, then body" {
    const body = [_]u8{ 0xde, 0xad, 0x00, 0xbe, 0xef, 0xff };
    const stamp: i64 = 0x0102_0304_0506_0708;
    var out: [ctx.header_len + 6 + body.len]u8 = undefined;
    const wrapped = try ctx.wrap(&out, "sess-1", stamp, &body);

    try testing.expectEqual(@as(usize, ctx.header_len + 6 + body.len), wrapped.len);
    try testing.expectEqual(@as(u8, 6), wrapped[0]);
    try testing.expectEqual(@as(u8, 0), wrapped[1]);
    try testing.expectEqualStrings("sess-1", wrapped[2..8]);

    // The timestamp sits immediately after the session id, little-endian.
    const stamp_at = ctx.length_prefix_len + 6;
    const stamp_bytes = [_]u8{ 0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01 };
    try testing.expectEqualSlices(u8, &stamp_bytes, wrapped[stamp_at..][0..ctx.timestamp_len]);

    const body_at = ctx.header_len + 6;
    try testing.expectEqualSlices(u8, &body, wrapped[body_at..]);

    const view = try ctx.unwrap(wrapped);
    try testing.expectEqualStrings("sess-1", view.session_id);
    try testing.expectEqual(stamp, view.ingress_received_at);
    try testing.expectEqualSlices(u8, &body, view.body);
}

test "session context: an absent session id keeps the timestamp and body" {
    // Every HTTP collection traverses the ingress, so the context is always
    // present; only the session id is optional.
    const body = "FNGR-body";
    var out: [ctx.header_len + body.len]u8 = undefined;
    const wrapped = try ctx.wrap(&out, "", 1757312346789, body);

    try testing.expectEqual(@as(usize, ctx.header_len + body.len), wrapped.len);
    try testing.expectEqual(@as(u8, 0), wrapped[0]);
    try testing.expectEqual(@as(u8, 0), wrapped[1]);

    const view = try ctx.unwrap(wrapped);
    try testing.expectEqual(@as(usize, 0), view.session_id.len);
    try testing.expectEqual(@as(i64, 1757312346789), view.ingress_received_at);
    try testing.expectEqualStrings(body, view.body);
}

test "session context: a zero timestamp round-trips as exactly 0" {
    var out: [ctx.header_len + 4 + 4]u8 = undefined;
    const wrapped = try ctx.wrap(&out, "abcd", 0, "body");
    const view = try ctx.unwrap(wrapped);
    try testing.expectEqual(@as(i64, 0), view.ingress_received_at);
}

test "session context: a negative timestamp is bit-preserved, not clamped" {
    // Epoch milliseconds are positive in practice, but the codec must not
    // reinterpret the i64 (a signed/unsigned mix-up would show here).
    var out: [ctx.header_len + 4 + 4]u8 = undefined;
    const wrapped = try ctx.wrap(&out, "abcd", -42, "body");
    const view = try ctx.unwrap(wrapped);
    try testing.expectEqual(@as(i64, -42), view.ingress_received_at);
}

test "session context: length prefix encodes the 128-byte cap in little-endian" {
    const session = [_]u8{'z'} ** ctx.max_session_id_len;
    var out: [ctx.header_len + ctx.max_session_id_len]u8 = undefined;
    const wrapped = try ctx.wrap(&out, &session, 1, &.{});

    try testing.expectEqual(@as(u8, @intCast(ctx.max_session_id_len)), wrapped[0]);
    try testing.expectEqual(@as(u8, 0), wrapped[1]);
    const view = try ctx.unwrap(wrapped);
    try testing.expectEqualSlices(u8, &session, view.session_id);
    try testing.expectEqual(@as(usize, 0), view.body.len);
}

test "session context: wrapping round-trips a body that contains the header bytes" {
    // A body starting with `\x04\x00\x01...` must not be mistaken for a nested
    // context: the header is positional and the body is the rest.
    const body = [_]u8{ 0x04, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 'F', 'P', 'K', 'G' };
    var out: [ctx.header_len + 4 + body.len]u8 = undefined;
    const wrapped = try ctx.wrap(&out, "abcd", 99, &body);
    const view = try ctx.unwrap(wrapped);
    try testing.expectEqualSlices(u8, &body, view.body);
    try testing.expectEqual(@as(i64, 99), view.ingress_received_at);
}

test "session context: wrap rejects invalid ids and undersized output" {
    var out: [ctx.header_len + 8]u8 = undefined;

    try testing.expectError(error.InvalidSessionId, ctx.wrap(&out, "bad id", 0, "body"));
    try testing.expectError(error.InvalidSessionId, ctx.wrap(&out, "sess\tic", 0, "body"));
    try testing.expectError(error.SessionIdTooLong, ctx.wrap(
        &out,
        &([_]u8{'a'} ** (ctx.max_session_id_len + 1)),
        0,
        "body",
    ));

    var tiny: [ctx.header_len + 3]u8 = undefined;
    try testing.expectError(error.BufferTooSmall, ctx.wrap(&tiny, "abcd", 0, "body"));
}

test "session context: unwrap rejects truncated and malformed payloads" {
    // Shorter than the u16 length field.
    try testing.expectError(error.Truncated, ctx.unwrap(&.{}));
    try testing.expectError(error.Truncated, ctx.unwrap(&.{0x04}));

    // Declares four session bytes but the payload ends inside them.
    try testing.expectError(error.Truncated, ctx.unwrap(&.{ 0x04, 0x00, 'a', 'b' }));

    // Session bytes complete, timestamp missing.
    const no_stamp = [_]u8{ 0x02, 0x00, 'a', 'b', 0, 0, 0, 0 };
    try testing.expectError(error.Truncated, ctx.unwrap(&no_stamp));

    // Declares more session bytes than the cap.
    try testing.expectError(error.SessionIdTooLong, ctx.unwrap(&.{ 0x7f, 0x01, 'a', 'b' }));

    // Declares a valid length whose bytes fail the charset.
    const bad_chars = [_]u8{ 0x02, 0x00, 'a', ' ' } ++ ([_]u8{0} ** ctx.timestamp_len);
    try testing.expectError(error.InvalidSessionId, ctx.unwrap(&bad_chars));
}
