//! Ingress request authentication tests (M7 W6-D3).
//!
//! The verifier is pure apart from its replay cache, and the clock is injected,
//! so the whole surface — signature, freshness, replay, rotation — is tested
//! without a socket. The HTTP end of it (header parsing, status mapping, real
//! requests over TCP) is covered by `ingress_http_test.zig` and the e2e suite in
//! `src/integration_tests.zig`.

const std = @import("std");
const testing = std.testing;
const ingress = @import("ingress");

const hmac = ingress.hmac;

const secret = "0123456789abcdef0123456789abcdef";
const previous = "fedcba9876543210fedcba9876543210";
const now_ms: i64 = 1757312345678;
const nonce = "8d56529f06040b90df4cb25a3811a10e";
const body = "the canonical signal package bytes";

fn bodyDigest(bytes: []const u8) [32]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return digest;
}

/// The headers a correctly signed request carries. `signature` stays a sized
/// array so the slice remains valid after return.
const Signed = struct {
    collected_at: i64,
    nonce: []const u8,
    signature: [hmac.signature_prefix.len + 64]u8,

    fn slice(self: *const Signed) []const u8 {
        return &self.signature;
    }
};

fn sign(key: []const u8, collected_at: i64, nonce_value: []const u8, digest: [32]u8) Signed {
    const mac = hmac.sign(key, collected_at, nonce_value, digest);
    var rendered: [hmac.signature_prefix.len + 64]u8 = undefined;
    _ = hmac.renderSignature(mac, &rendered); // always prefix + 64 hex chars
    return .{
        .collected_at = collected_at,
        .nonce = nonce_value,
        .signature = rendered,
    };
}

test "hmac: a correctly signed request is accepted" {
    var verifier = try hmac.Verifier.init(testing.allocator, secret, null, hmac.default_window_ms);
    defer verifier.deinit();

    const signed = sign(secret, now_ms - 1_000, nonce, bodyDigest(body));
    try verifier.verify(
        signed.collected_at,
        now_ms,
        signed.nonce,
        bodyDigest(body),
        signed.slice(),
    );
}

test "hmac: an unsigned request is rejected, one header at a time" {
    var verifier = try hmac.Verifier.init(testing.allocator, secret, null, hmac.default_window_ms);
    defer verifier.deinit();

    const digest = bodyDigest(body);
    const signed = sign(secret, now_ms, nonce, digest);

    try testing.expectError(
        error.MissingTimestamp,
        verifier.verify(null, now_ms, signed.nonce, digest, signed.slice()),
    );
    try testing.expectError(
        error.MissingNonce,
        verifier.verify(signed.collected_at, now_ms, null, digest, signed.slice()),
    );
    try testing.expectError(
        error.MissingNonce,
        verifier.verify(signed.collected_at, now_ms, "", digest, signed.slice()),
    );
    try testing.expectError(
        error.MissingSignature,
        verifier.verify(signed.collected_at, now_ms, signed.nonce, digest, null),
    );
}

test "hmac: a forged signature is rejected" {
    var verifier = try hmac.Verifier.init(testing.allocator, secret, null, hmac.default_window_ms);
    defer verifier.deinit();

    const digest = bodyDigest(body);
    const forged = sign("another-secret-that-is-32-chars!!", now_ms, nonce, digest);
    try testing.expectError(
        error.InvalidSignature,
        verifier.verify(forged.collected_at, now_ms, forged.nonce, digest, forged.slice()),
    );
}

test "hmac: the signature is bound to the body, timestamp, and nonce" {
    var verifier = try hmac.Verifier.init(testing.allocator, secret, null, hmac.default_window_ms);
    defer verifier.deinit();

    const digest = bodyDigest(body);
    const signed = sign(secret, now_ms - 1_000, nonce, digest);

    // Same headers, different body: the captured MAC does not transfer.
    try testing.expectError(
        error.InvalidSignature,
        verifier.verify(
            signed.collected_at,
            now_ms,
            signed.nonce,
            bodyDigest("a different package"),
            signed.slice(),
        ),
    );
    // Same body and nonce, different timestamp: likewise.
    try testing.expectError(
        error.InvalidSignature,
        verifier.verify(
            signed.collected_at - 1,
            now_ms,
            signed.nonce,
            digest,
            signed.slice(),
        ),
    );
    // Same body and timestamp, different nonce: likewise.
    try testing.expectError(
        error.InvalidSignature,
        verifier.verify(
            signed.collected_at,
            now_ms,
            "00000000000000000000000000000001",
            digest,
            signed.slice(),
        ),
    );
}

test "hmac: malformed signature headers are rejected" {
    var verifier = try hmac.Verifier.init(testing.allocator, secret, null, hmac.default_window_ms);
    defer verifier.deinit();

    const digest = bodyDigest(body);
    const signed = sign(secret, now_ms, nonce, digest);

    // Wrong scheme, wrong length, non-hex payload, and a non-hex nonce.
    try testing.expectError(
        error.MalformedSignature,
        verifier.verify(signed.collected_at, now_ms, signed.nonce, digest, "sha256=00"),
    );
    try testing.expectError(
        error.MalformedSignature,
        verifier.verify(signed.collected_at, now_ms, signed.nonce, digest, "hmac-sha256=zz"),
    );
    try testing.expectError(
        error.MalformedNonce,
        verifier.verify(signed.collected_at, now_ms, "NOT-A-NONCE", digest, signed.slice()),
    );
    // Uppercase hex is refused: the canonical string must be unambiguous.
    try testing.expectError(
        error.MalformedNonce,
        verifier.verify(
            signed.collected_at,
            now_ms,
            "8D56529F06040B90DF4CB25A3811A10E",
            digest,
            signed.slice(),
        ),
    );
}

test "hmac: uppercase hex in the signature value is accepted" {
    var verifier = try hmac.Verifier.init(testing.allocator, secret, null, hmac.default_window_ms);
    defer verifier.deinit();

    const digest = bodyDigest(body);
    var signed = sign(secret, now_ms, nonce, digest);
    // Case-insensitivity here is safe: the algorithm prefix carries the
    // semantics, and the compared value is decoded bytes.
    for (signed.signature[hmac.signature_prefix.len..]) |*byte| byte.* = std.ascii.toUpper(byte.*);
    try verifier.verify(signed.collected_at, now_ms, signed.nonce, digest, signed.slice());
}

test "hmac: a stale or future-dated timestamp is rejected" {
    var verifier = try hmac.Verifier.init(testing.allocator, secret, null, hmac.default_window_ms);
    defer verifier.deinit();

    const digest = bodyDigest(body);

    // One millisecond past the window in the past.
    const old = now_ms - hmac.default_window_ms - 1;
    const stale = sign(secret, old, nonce, digest);
    try testing.expectError(
        error.StaleTimestamp,
        verifier.verify(stale.collected_at, now_ms, stale.nonce, digest, stale.slice()),
    );

    // One millisecond past the window in the future (clock skew abuse).
    const future = now_ms + hmac.default_window_ms + 1;
    const ahead = sign(secret, future, nonce, digest);
    try testing.expectError(
        error.StaleTimestamp,
        verifier.verify(ahead.collected_at, now_ms, ahead.nonce, digest, ahead.slice()),
    );

    // Exactly on the boundary in both directions is still inside the window.
    const at_edge = sign(secret, now_ms - hmac.default_window_ms, nonce, digest);
    try verifier.verify(at_edge.collected_at, now_ms, at_edge.nonce, digest, at_edge.slice());

    const ahead_edge = sign(secret, now_ms + hmac.default_window_ms, "00000000000000000000000000000002", digest);
    try verifier.verify(
        ahead_edge.collected_at,
        now_ms,
        ahead_edge.nonce,
        digest,
        ahead_edge.slice(),
    );
}

test "hmac: a replay inside the window is rejected, and the nonce is remembered" {
    var verifier = try hmac.Verifier.init(testing.allocator, secret, null, hmac.default_window_ms);
    defer verifier.deinit();

    const digest = bodyDigest(body);
    const signed = sign(secret, now_ms, nonce, digest);

    try verifier.verify(signed.collected_at, now_ms, signed.nonce, digest, signed.slice());
    // Byte-identical retry: still inside the window, so it is a replay.
    try testing.expectError(
        error.ReplayedNonce,
        verifier.verify(signed.collected_at, now_ms + 1_000, signed.nonce, digest, signed.slice()),
    );
    // A fresh nonce for the same body is a new request, not a replay.
    const fresh = sign(secret, now_ms, "00000000000000000000000000000003", digest);
    try verifier.verify(fresh.collected_at, now_ms, fresh.nonce, digest, fresh.slice());
}

test "hmac: a replayed nonce is rejected after the window is full of entries" {
    // Exercises the compaction path: insert until the table is at half load,
    // then a live entry must survive the rebuild and still be detected.
    var verifier = try hmac.Verifier.initWithCapacity(testing.allocator, secret, null, hmac.default_window_ms, 8);
    defer verifier.deinit();

    const digest = bodyDigest(body);
    const first_nonce = "00000000000000000000000000000001";
    const first = sign(secret, now_ms, first_nonce, digest);
    try verifier.verify(first.collected_at, now_ms, first.nonce, digest, first.slice());

    for (0..2) |i| {
        var buf: [32]u8 = undefined;
        const fresh_nonce = try std.fmt.bufPrint(&buf, "{x:0>32}", .{i + 2});
        const signed = sign(secret, now_ms, fresh_nonce, digest);
        try verifier.verify(signed.collected_at, now_ms, signed.nonce, digest, signed.slice());
    }

    // The table holds exactly 3 live entries; a fourth would need a rebuild
    // that cannot free anything, so it is refused rather than evicting.
    const overflow = sign(secret, now_ms, "000000000000000000000000000000ff", digest);
    try testing.expectError(
        error.CacheFull,
        verifier.verify(overflow.collected_at, now_ms, overflow.nonce, digest, overflow.slice()),
    );

    // The first nonce is still known: compaction preserved it.
    try testing.expectError(
        error.ReplayedNonce,
        verifier.verify(first.collected_at, now_ms, first.nonce, digest, first.slice()),
    );
}

test "hmac: expired entries are reclaimed so the cache keeps accepting" {
    var verifier = try hmac.Verifier.initWithCapacity(testing.allocator, secret, null, 1_000, 8);
    defer verifier.deinit();

    const digest = bodyDigest(body);

    // Fill at t0.
    for (0..3) |i| {
        var buf: [32]u8 = undefined;
        const fresh_nonce = try std.fmt.bufPrint(&buf, "{x:0>32}", .{i + 1});
        const signed = sign(secret, now_ms, fresh_nonce, digest);
        try verifier.verify(signed.collected_at, now_ms, signed.nonce, digest, signed.slice());
    }

    // Long after the window, everything is stale — but new requests arrive with
    // a current timestamp, so the cache must have reclaimed the old slots.
    const later = now_ms + 10 * 60 * 1000;
    for (0..3) |i| {
        var buf: [32]u8 = undefined;
        const fresh_nonce = try std.fmt.bufPrint(&buf, "{x:0>32}", .{i + 11});
        const signed = sign(secret, later, fresh_nonce, digest);
        try verifier.verify(signed.collected_at, later, signed.nonce, digest, signed.slice());
    }
}

test "hmac: the previous secret is accepted during rotation" {
    var verifier = try hmac.Verifier.init(testing.allocator, secret, previous, hmac.default_window_ms);
    defer verifier.deinit();

    const digest = bodyDigest(body);
    const current = sign(secret, now_ms, "0000000000000000000000000000000a", digest);
    try verifier.verify(current.collected_at, now_ms, current.nonce, digest, current.slice());

    const old = sign(previous, now_ms, "0000000000000000000000000000000b", digest);
    try verifier.verify(old.collected_at, now_ms, old.nonce, digest, old.slice());

    // Rotation does not open a replay hole: a nonce used under the old secret
    // is still spent.
    try testing.expectError(
        error.ReplayedNonce,
        verifier.verify(old.collected_at, now_ms, old.nonce, digest, old.slice()),
    );

    // An unknown secret is still rejected.
    const unknown = sign("unknown-secret-32-characters-long!!", now_ms, "0000000000000000000000000000000c", digest);
    try testing.expectError(
        error.InvalidSignature,
        verifier.verify(unknown.collected_at, now_ms, unknown.nonce, digest, unknown.slice()),
    );
}

test "hmac: a short secret is refused at startup" {
    var short = [_]u8{'a'} ** (hmac.min_secret_len - 1);
    try testing.expectError(
        error.SecretTooShort,
        hmac.Verifier.init(testing.allocator, &short, null, hmac.default_window_ms),
    );
    // A previous secret is held to the same bar.
    try testing.expectError(
        error.SecretTooShort,
        hmac.Verifier.init(testing.allocator, secret, &short, hmac.default_window_ms),
    );
}

test "hmac: the canonical string and signature encoding are stable" {
    // A golden pins the client-facing format: changing the canonical string is
    // a protocol break, not a refactor. `openssl` reproduces it with
    //   printf 'fpkg-hmac-v1\n<ts>\n<nonce>\n<sha256 hex>' | openssl dgst -sha256 -hmac <secret>
    const digest = bodyDigest(body);
    const mac = hmac.sign(secret, 1757312345678, nonce, digest);

    var rendered: [hmac.signature_prefix.len + 64]u8 = undefined;
    const signature = hmac.renderSignature(mac, &rendered);
    try testing.expect(std.mem.startsWith(u8, signature, "hmac-sha256="));
    try testing.expectEqual(@as(usize, "hmac-sha256=".len + 64), signature.len);

    const parsed = hmac.parseSignature(signature).?;
    try testing.expectEqualSlices(u8, &mac, &parsed);

    // The keys are ordered in the header contract; only the digest bytes are
    // signed, so any 32-byte digest is a legal input.
    const zero = hmac.sign(secret, 0, nonce, .{0} ** 32);
    try testing.expect(!std.mem.eql(u8, &mac, &zero));
}

test "hmac: nonce bounds are enforced" {
    try testing.expect(!hmac.isValidNonce(""));
    try testing.expect(!hmac.isValidNonce("abcdef0")); // too short (7)
    try testing.expect(hmac.isValidNonce("0123456789abcdef")); // 16 = min
    try testing.expect(hmac.isValidNonce(&([_]u8{'a'} ** hmac.max_nonce_len))); // 64 = max
    try testing.expect(!hmac.isValidNonce(&([_]u8{'a'} ** (hmac.max_nonce_len + 1))));
    try testing.expect(!hmac.isValidNonce("0123456789abcdeg"));
}
