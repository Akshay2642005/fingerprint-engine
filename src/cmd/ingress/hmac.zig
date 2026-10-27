//! Ingress request authentication (M7 W6-D3, D-v1-2): an HMAC over the request
//! body keyed by a deployment secret, plus a freshness/replay window.
//!
//! The engine never sees secrets (D5). This check lives at the HTTP boundary,
//! before the body is wrapped and forwarded, and the worker stays unaware of
//! it: a request that fails here is never turned into a frame.
//!
//! Three headers carry the proof, all `x-fpkg-`-namespaced like the rest of the
//! ingest contract:
//!
//!   x-fpkg-collected-at: <epoch milliseconds, decimal>
//!   x-fpkg-nonce:        <16–64 lowercase hex chars, fresh per attempt>
//!   x-fpkg-signature:    hmac-sha256=<64 lowercase hex chars>
//!
//! The signed string binds the timestamp, the nonce, and the body, so a
//! captured signature cannot be re-aimed at a different body or timestamp:
//!
//!   "fpkg-hmac-v1\n<collected_at>\n<nonce>\n<sha256(body) as lowercase hex>"
//!
//! Verification is fail-closed: when the ingress has a secret, an unsigned
//! request is rejected, not passed through. A stale (older than the window) or
//! future-dated timestamp is rejected before the MAC is even checked, and a
//! valid request's nonce is remembered so a byte-identical replay inside the
//! window is rejected.
//!
//! Note on the browser SDK: it cannot hold a secret, so enabling this obliges
//! callers to sign server-side (the platform gateway or a trusted edge). It is
//! off unless `FPKG_HMAC_SECRET` is set.
//!
//! Rotation: `FPKG_HMAC_SECRET_PREVIOUS` is accepted alongside the current
//! secret, so a deployment can roll the key without dropping in-flight signed
//! requests. Remove the previous secret once the window has elapsed.

const std = @import("std");

/// Prefix on the `x-fpkg-signature` value. Names the algorithm so a future
/// scheme can be added without parsing ambiguity.
pub const signature_prefix = "hmac-sha256=";

/// Default freshness/replay window: five minutes (the M7 plan's default).
pub const default_window_ms: i64 = 5 * 60 * 1000;

/// Nonce bounds. 16 hex chars is a 64-bit nonce; 64 hex chars is 256 bits.
pub const min_nonce_len: usize = 16;
pub const max_nonce_len: usize = 64;

/// Number of replay-cache slots. At the default window this covers roughly
/// 200 req/s sustained per ingress instance; above that the cache fills and
/// requests are refused (fail closed) rather than silently allowing replays.
pub const default_capacity: usize = 1 << 16;

/// A secret shorter than this is refused at startup.
pub const min_secret_len: usize = 32;

/// Domain separation for the canonical string.
const domain = "fpkg-hmac-v1";

/// Verification failures. Every one of them is a client error except
/// `CacheFull` (a deployment capacity error) and `OutOfMemory`.
pub const Error = error{
    MissingTimestamp,
    StaleTimestamp,
    MissingNonce,
    MalformedNonce,
    MissingSignature,
    MalformedSignature,
    InvalidSignature,
    ReplayedNonce,
    CacheFull,
    OutOfMemory,
};

/// One replay-cache slot. `expires_ms == 0` marks an empty slot; real
/// collection timestamps are always non-zero absolute epoch values.
const Entry = struct {
    key: [16]u8 = .{0} ** 16,
    expires_ms: i64 = 0,
};

/// Verifies request signatures and remembers accepted nonces for the window.
/// The ingress serves one connection at a time, so the cache needs no locking.
pub const Verifier = struct {
    secrets: [2][]const u8 = .{ "", "" },
    secret_count: usize = 0,
    window_ms: i64,
    allocator: std.mem.Allocator,
    slots: []Entry,
    scratch: []Entry,
    count: usize = 0,

    pub fn init(
        alloc: std.mem.Allocator,
        current: []const u8,
        previous: ?[]const u8,
        window_ms: i64,
    ) !Verifier {
        return initWithCapacity(alloc, current, previous, window_ms, default_capacity);
    }

    /// Same as `init` with an explicit table size (a power of two, at least 4).
    /// Only tests use this: the real capacity is `default_capacity`, sized for
    /// the default window at roughly 200 req/s.
    pub fn initWithCapacity(
        alloc: std.mem.Allocator,
        current: []const u8,
        previous: ?[]const u8,
        window_ms: i64,
        capacity: usize,
    ) !Verifier {
        if (current.len < min_secret_len) return error.SecretTooShort;
        if (previous) |prev| {
            if (prev.len < min_secret_len) return error.SecretTooShort;
        }
        if (capacity < 4 or !std.math.isPowerOfTwo(capacity)) return error.InvalidCapacity;
        const slots = try alloc.alloc(Entry, capacity);
        errdefer alloc.free(slots);
        const scratch = try alloc.alloc(Entry, capacity);
        @memset(slots, .{});
        @memset(scratch, .{});

        var verifier = Verifier{
            .window_ms = window_ms,
            .allocator = alloc,
            .slots = slots,
            .scratch = scratch,
        };
        verifier.secrets[0] = current;
        verifier.secret_count = 1;
        if (previous) |prev| {
            verifier.secrets[1] = prev;
            verifier.secret_count = 2;
        }
        return verifier;
    }

    pub fn deinit(self: *Verifier) void {
        self.allocator.free(self.slots);
        self.allocator.free(self.scratch);
        self.* = undefined;
    }

    /// Verifies one request. `now_ms` is injected so the window logic is
    /// testable without a clock. `nonce = ""` and a null signature are the
    /// "header absent" cases and are rejected.
    pub fn verify(
        self: *Verifier,
        collected_at: ?i64,
        now_ms: i64,
        nonce: ?[]const u8,
        body_digest: [32]u8,
        signature: ?[]const u8,
    ) Error!void {
        const timestamp = collected_at orelse return error.MissingTimestamp;

        const nonce_value = nonce orelse return error.MissingNonce;
        if (nonce_value.len == 0) return error.MissingNonce;
        if (!isValidNonce(nonce_value)) return error.MalformedNonce;

        const signature_value = signature orelse return error.MissingSignature;
        const provided = parseSignature(signature_value) orelse return error.MalformedSignature;

        // Freshness first: a stale timestamp is unauthorised, and skipping the
        // MAC keeps a flood of expired replays cheap to reject.
        if (timestamp > now_ms + self.window_ms or now_ms - timestamp > self.window_ms) {
            return error.StaleTimestamp;
        }

        // Constant-time compare against every accepted secret (no early exit on
        // the secret index, so rotation does not leak which key matched).
        var matched = false;
        for (self.secrets[0..self.secret_count]) |secret| {
            const expected = mac(secret, timestamp, nonce_value, body_digest);
            if (std.crypto.timing_safe.eql([32]u8, expected, provided)) matched = true;
        }
        if (!matched) return error.InvalidSignature;

        // Only a request that proved possession of the key may occupy a cache
        // slot, so forged traffic cannot evict legitimate nonces.
        const key = nonceKey(nonce_value);
        if (self.contains(key, now_ms)) return error.ReplayedNonce;
        try self.remember(key, now_ms, timestamp + self.window_ms);
    }

    fn contains(self: *Verifier, key: [16]u8, now_ms: i64) bool {
        const mask = self.slots.len - 1;
        var index = slotIndex(key) & mask;
        var steps: usize = 0;
        while (steps < self.slots.len) : (steps += 1) {
            const entry = self.slots[index];
            if (entry.expires_ms == 0) return false; // empty slot ends the chain
            if (entry.expires_ms > now_ms and std.mem.eql(u8, &entry.key, &key)) return true;
            index = (index + 1) & mask;
        }
        return false;
    }

    fn remember(self: *Verifier, key: [16]u8, now_ms: i64, expires_ms: i64) Error!void {
        // Keep the table at or below half load so probe chains stay short and a
        // rebuild always has room. Expired entries are reclaimed wholesale.
        if ((self.count + 1) * 2 >= self.slots.len) {
            self.compact(now_ms);
            if ((self.count + 1) * 2 >= self.slots.len) return error.CacheFull;
        }

        const mask = self.slots.len - 1;
        var index = slotIndex(key) & mask;
        var steps: usize = 0;
        while (steps < self.slots.len) : (steps += 1) {
            const entry = &self.slots[index];
            if (entry.expires_ms == 0 or entry.expires_ms <= now_ms) {
                // Reusing an expired slot does not grow the live set; writing
                // into an empty one does.
                if (entry.expires_ms == 0) self.count += 1;
                entry.* = .{ .key = key, .expires_ms = expires_ms };
                return;
            }
            index = (index + 1) & mask;
        }
        return error.CacheFull;
    }

    /// Rebuilds the table without the entries that have expired, preserving the
    /// probe chains (rehashing every survivor into the scratch table, then
    /// swapping). Never breaks a live entry's lookup.
    fn compact(self: *Verifier, now_ms: i64) void {
        @memset(self.scratch, .{});
        const mask = self.scratch.len - 1;
        var live: usize = 0;
        for (self.slots) |entry| {
            if (entry.expires_ms == 0 or entry.expires_ms <= now_ms) continue;
            var index = slotIndex(entry.key) & mask;
            while (self.scratch[index].expires_ms != 0) index = (index + 1) & mask;
            self.scratch[index] = entry;
            live += 1;
        }
        const previous = self.slots;
        self.slots = self.scratch;
        self.scratch = previous;
        self.count = live;
    }
};

/// True for a well-formed nonce: 16–64 lowercase hex characters. Lowercase only
/// keeps the canonical string unambiguous between client and ingress.
pub fn isValidNonce(nonce: []const u8) bool {
    if (nonce.len < min_nonce_len or nonce.len > max_nonce_len) return false;
    for (nonce) |byte| {
        const hex = (byte >= '0' and byte <= '9') or (byte >= 'a' and byte <= 'f');
        if (!hex) return false;
    }
    return true;
}

/// Parses `hmac-sha256=<64 hex>` (hex case-insensitive) into raw bytes.
pub fn parseSignature(value: []const u8) ?[32]u8 {
    if (!std.mem.startsWith(u8, value, signature_prefix)) return null;
    const hex = value[signature_prefix.len..];
    if (hex.len != 64) return null;
    var out: [32]u8 = undefined;
    for (0..32) |i| {
        const hi = hexNibble(hex[i * 2]) orelse return null;
        const lo = hexNibble(hex[i * 2 + 1]) orelse return null;
        out[i] = (hi << 4) | lo;
    }
    return out;
}

/// Renders the `x-fpkg-signature` value for a MAC. Used by clients, tests, and
/// the documentation example, so the wire format has one implementation.
pub fn renderSignature(computed: [32]u8, out: *[signature_prefix.len + 64]u8) []const u8 {
    @memcpy(out[0..signature_prefix.len], signature_prefix);
    _ = std.fmt.bufPrint(out[signature_prefix.len..], "{s}", .{
        std.fmt.fmtSliceHexLower(&computed),
    }) catch unreachable;
    return out;
}

/// Computes the MAC for a request (exported so a client or test can sign).
pub fn sign(
    secret: []const u8,
    collected_at: i64,
    nonce: []const u8,
    body_digest: [32]u8,
) [32]u8 {
    return mac(secret, collected_at, nonce, body_digest);
}

fn mac(secret: []const u8, collected_at: i64, nonce: []const u8, body_digest: [32]u8) [32]u8 {
    var hmac = std.crypto.auth.hmac.sha2.HmacSha256.init(secret);
    hmac.update(domain);
    hmac.update("\n");
    var timestamp_buf: [24]u8 = undefined;
    const timestamp = std.fmt.bufPrint(&timestamp_buf, "{d}", .{collected_at}) catch unreachable;
    hmac.update(timestamp);
    hmac.update("\n");
    hmac.update(nonce);
    hmac.update("\n");
    var digest_hex: [64]u8 = undefined;
    _ = std.fmt.bufPrint(&digest_hex, "{s}", .{std.fmt.fmtSliceHexLower(&body_digest)}) catch unreachable;
    hmac.update(&digest_hex);
    var out: [32]u8 = undefined;
    hmac.final(&out);
    return out;
}

/// Replay-cache key: 128 bits of SHA-256 over the nonce. The nonce itself is
/// public; hashing it just gives the fixed-size table a uniformly distributed
/// key for arbitrary-length input.
fn nonceKey(nonce: []const u8) [16]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(nonce, &digest, .{});
    var key: [16]u8 = undefined;
    @memcpy(&key, digest[0..16]);
    return key;
}

fn slotIndex(key: [16]u8) usize {
    return std.mem.readInt(u64, key[0..8], .little);
}

fn hexNibble(byte: u8) ?u8 {
    return switch (byte) {
        '0'...'9' => byte - '0',
        'a'...'f' => byte - 'a' + 10,
        'A'...'F' => byte - 'A' + 10,
        else => null,
    };
}
