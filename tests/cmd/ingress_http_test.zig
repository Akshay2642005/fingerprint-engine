//! Ingress HTTP server unit tests (S4-c, story s4-ingress-http).
//!
//! The parser and the status mapping are pure — no sockets, no io — so they
//! are tested here in isolation; the socket path is covered by the e2e tests
//! in src/integration_tests.zig.

const std = @import("std");
const testing = std.testing;
const ingress = @import("ingress");

const http = ingress.http;

test "ingress http: parses a well-formed POST head" {
    const head =
        "POST /v1/fingerprints HTTP/1.1\r\n" ++
        "content-type: application/octet-stream\r\n" ++
        "content-length: 4096\r\n" ++
        "x-fpkg-schema-version: 2\r\n" ++
        "x-fpkg-package-id: 8d56529f06040b90df4cb25a3811a10e\r\n" ++
        "x-fpkg-integrity: sha256-969f0e446e6aeca223b72d5d50a7f1701c9b04c71fd1d7fcdda65b6a046fbfc3\r\n";

    const parsed = try http.parseHead(head);
    try testing.expectEqual(http.Method.post, parsed.method);
    try testing.expectEqualStrings("/v1/fingerprints", parsed.target);
    try testing.expectEqual(@as(?u64, 4096), parsed.content_length);
    try testing.expectEqual(@as(?u8, 2), parsed.schema_version);
    try testing.expectEqualStrings("8d56529f06040b90df4cb25a3811a10e", parsed.package_id.?);
    try testing.expectEqualStrings(
        "sha256-969f0e446e6aeca223b72d5d50a7f1701c9b04c71fd1d7fcdda65b6a046fbfc3",
        parsed.integrity.?,
    );
    try testing.expect(!parsed.chunked);
}

test "ingress http: parses a GET /healthz head" {
    const parsed = try http.parseHead("GET /healthz HTTP/1.1\r\n");
    try testing.expectEqual(http.Method.get, parsed.method);
    try testing.expectEqualStrings("/healthz", parsed.target);
    try testing.expectEqual(@as(?u64, null), parsed.content_length);
}

test "ingress http: header names are case-insensitive" {
    const parsed = try http.parseHead(
        "POST / HTTP/1.1\r\n" ++
            "Content-Length: 42\r\n" ++
            "X-FPKG-Schema-Version: 1\r\n" ++
            "X-FPKG-Session-Id: 8d56529f-0604-0b90-df4c-b25a3811a10e\r\n",
    );
    try testing.expectEqual(@as(?u64, 42), parsed.content_length);
    try testing.expectEqual(@as(?u8, 1), parsed.schema_version);
    try testing.expectEqualStrings(
        "8d56529f-0604-0b90-df4c-b25a3811a10e",
        parsed.session_id.?,
    );
}

test "ingress http: a missing session header parses as null" {
    const parsed = try http.parseHead("POST / HTTP/1.1\r\ncontent-length: 0\r\n");
    try testing.expectEqual(@as(?[]const u8, null), parsed.session_id);
}

test "ingress http: the CORS preflight allows x-fpkg-session-id" {
    // ADR-013 §4: the browser SDK must be able to send the header without a
    // preflight failure, so the allow-list is a contract, not an internal
    // detail.
    try testing.expect(std.mem.indexOf(u8, http.HttpServer.cors_allow_headers, "x-fpkg-session-id") != null);
}

test "ingress http: parses the request-signature headers" {
    // M7 W6-D3: the authentication triple is carried in headers, not in the
    // body, so the ingress never has to parse a package to authenticate it.
    const parsed = try http.parseHead(
        "POST / HTTP/1.1\r\n" ++
            "content-length: 4\r\n" ++
            "x-fpkg-collected-at: 1757312345678\r\n" ++
            "x-fpkg-nonce: 8d56529f06040b90df4cb25a3811a10e\r\n" ++
            "x-fpkg-signature: hmac-sha256=969f0e446e6aeca223b72d5d50a7f1701c9b04c71fd1d7fcdda65b6a046fbfc3\r\n",
    );
    try testing.expectEqual(@as(?i64, 1757312345678), parsed.collected_at);
    try testing.expectEqualStrings("8d56529f06040b90df4cb25a3811a10e", parsed.nonce.?);
    try testing.expect(std.mem.startsWith(u8, parsed.signature.?, "hmac-sha256="));
}

test "ingress http: missing signature headers parse as null" {
    const parsed = try http.parseHead("POST / HTTP/1.1\r\ncontent-length: 0\r\n");
    try testing.expectEqual(@as(?i64, null), parsed.collected_at);
    try testing.expectEqual(@as(?[]const u8, null), parsed.nonce);
    try testing.expectEqual(@as(?[]const u8, null), parsed.signature);
}

test "ingress http: a non-numeric collected-at is a header error" {
    try testing.expectError(
        error.MalformedHeader,
        http.parseHead("POST / HTTP/1.1\r\nx-fpkg-collected-at: yesterday\r\n"),
    );
}

test "ingress http: the CORS preflight allows the signature headers" {
    // A signing client may be a browser-adjacent gateway doing a preflight, so
    // the triple belongs in the allow-list for the same reason the session id
    // does.
    for ([_][]const u8{ "x-fpkg-collected-at", "x-fpkg-nonce", "x-fpkg-signature" }) |header| {
        try testing.expect(std.mem.indexOf(u8, http.HttpServer.cors_allow_headers, header) != null);
    }
}

test "ingress http: marks chunked requests" {
    const parsed = try http.parseHead("POST / HTTP/1.1\r\ntransfer-encoding: chunked\r\n");
    try testing.expect(parsed.chunked);
}

test "ingress http: rejects malformed request lines" {
    try testing.expectError(error.MalformedRequestLine, http.parseHead(""));
    try testing.expectError(error.MalformedRequestLine, http.parseHead("POST\r\n"));
    try testing.expectError(error.MalformedRequestLine, http.parseHead("POST / HTTP/1.1 extra\r\n"));
}

test "ingress http: rejects unsupported methods and versions" {
    const parsed1 = try http.parseHead("PUT / HTTP/1.1\r\n");
    try testing.expectEqual(http.Method.other, parsed1.method);
    try testing.expectError(error.UnsupportedVersion, http.parseHead("POST / HTTP/1.2\r\n"));
}

test "ingress http: rejects malformed headers" {
    try testing.expectError(error.MalformedHeader, http.parseHead("POST / HTTP/1.1\r\nnocolon\r\n"));
    try testing.expectError(error.MalformedHeader, http.parseHead("POST / HTTP/1.1\r\ncontent-length: soon\r\n"));
}

test "ingress http: maps worker status bytes to HTTP status" {
    try testing.expectEqual(@as(u16, 200), http.statusToHttp(0)); // ok
    try testing.expectEqual(@as(u16, 400), http.statusToHttp(1)); // invalid_request
    try testing.expectEqual(@as(u16, 400), http.statusToHttp(2)); // invalid_payload
    try testing.expectEqual(@as(u16, 415), http.statusToHttp(3)); // unsupported_version
    try testing.expectEqual(@as(u16, 400), http.statusToHttp(4)); // invalid_input
    try testing.expectEqual(@as(u16, 413), http.statusToHttp(5)); // buffer_overflow
    try testing.expectEqual(@as(u16, 502), http.statusToHttp(6)); // out_of_memory
    try testing.expectEqual(@as(u16, 502), http.statusToHttp(7)); // internal_error
    try testing.expectEqual(@as(u16, 502), http.statusToHttp(9)); // unknown
}

test "ingress http: responses classify into the three metric buckets" {
    try testing.expectEqual(ingress.metrics.StatusClass.@"2xx", http.statusClass(200));
    try testing.expectEqual(ingress.metrics.StatusClass.@"2xx", http.statusClass(204));
    try testing.expectEqual(ingress.metrics.StatusClass.@"4xx", http.statusClass(400));
    try testing.expectEqual(ingress.metrics.StatusClass.@"4xx", http.statusClass(404));
    try testing.expectEqual(ingress.metrics.StatusClass.@"4xx", http.statusClass(413));
    try testing.expectEqual(ingress.metrics.StatusClass.@"4xx", http.statusClass(499));
    try testing.expectEqual(ingress.metrics.StatusClass.@"5xx", http.statusClass(500));
    try testing.expectEqual(ingress.metrics.StatusClass.@"5xx", http.statusClass(502));
    try testing.expectEqual(ingress.metrics.StatusClass.@"5xx", http.statusClass(503));
}

test "ingress http: auth failures map to the catalogued rejection reasons" {
    // ADR-014 / observability.md §Ingress: missing, malformed, forged, stale,
    // replayed, cache_full. The mapping is total over hmac.Error by design.
    const AuthReason = ingress.metrics.AuthReason;
    try testing.expectEqual(AuthReason.missing, http.authReason(error.MissingTimestamp));
    try testing.expectEqual(AuthReason.missing, http.authReason(error.MissingNonce));
    try testing.expectEqual(AuthReason.missing, http.authReason(error.MissingSignature));
    try testing.expectEqual(AuthReason.malformed, http.authReason(error.MalformedNonce));
    try testing.expectEqual(AuthReason.malformed, http.authReason(error.MalformedSignature));
    try testing.expectEqual(AuthReason.stale, http.authReason(error.StaleTimestamp));
    try testing.expectEqual(AuthReason.forged, http.authReason(error.InvalidSignature));
    try testing.expectEqual(AuthReason.replayed, http.authReason(error.ReplayedNonce));
    try testing.expectEqual(AuthReason.cache_full, http.authReason(error.CacheFull));
    try testing.expectEqual(AuthReason.cache_full, http.authReason(error.OutOfMemory));
}

test "ingress http: the registry renders the ADR-014 catalog" {
    var registry = ingress.metrics.Metrics{};
    registry.requests_total.inc(.{ .status = .@"2xx" });
    registry.requests_total.inc(.{ .status = .@"4xx" });
    registry.auth_rejections_total.inc(.{ .reason = .replayed });
    registry.request_duration_seconds.observe(0.003);
    registry.replay_cache_entries.set(12);
    registry.replay_cache_capacity.set(65536);
    registry.worker_pool_healthy.set(2);

    var buffer: [16 * 1024]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    try ingress.metrics.render(&registry, stream.writer().any());
    const text = stream.getWritten();

    // Names, types, and label sets are the contract the scraper and alert
    // rules depend on. `build_info` and `ready` belong to the scrape preamble,
    // so the registry must not duplicate them.
    try testing.expect(std.mem.indexOf(u8, text, "# TYPE fpkg_ingress_requests_total counter\n") != null);
    try testing.expect(std.mem.indexOf(u8, text, "fpkg_ingress_requests_total{status=\"2xx\"} 1\n") != null);
    try testing.expect(std.mem.indexOf(u8, text, "fpkg_ingress_requests_total{status=\"4xx\"} 1\n") != null);
    try testing.expect(std.mem.indexOf(u8, text, "fpkg_ingress_requests_total{status=\"5xx\"} 0\n") != null);
    try testing.expect(std.mem.indexOf(u8, text, "# TYPE fpkg_ingress_request_duration_seconds histogram\n") != null);
    try testing.expect(std.mem.indexOf(u8, text, "fpkg_ingress_request_duration_seconds_count 1\n") != null);
    try testing.expect(std.mem.indexOf(u8, text, "# TYPE fpkg_ingress_auth_rejections_total counter\n") != null);
    try testing.expect(std.mem.indexOf(u8, text, "fpkg_ingress_auth_rejections_total{reason=\"replayed\"} 1\n") != null);
    try testing.expect(std.mem.indexOf(u8, text, "fpkg_ingress_replay_cache_entries 12\n") != null);
    try testing.expect(std.mem.indexOf(u8, text, "fpkg_ingress_replay_cache_capacity 65536\n") != null);
    try testing.expect(std.mem.indexOf(u8, text, "fpkg_ingress_worker_pool_healthy 2\n") != null);
    try testing.expect(std.mem.indexOf(u8, text, "fpkg_ingress_build_info") == null);
    try testing.expect(std.mem.indexOf(u8, text, "fpkg_ingress_ready") == null);
}
