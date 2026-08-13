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
            "X-FPKG-Schema-Version: 1\r\n",
    );
    try testing.expectEqual(@as(?u64, 42), parsed.content_length);
    try testing.expectEqual(@as(?u8, 1), parsed.schema_version);
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
    try testing.expectError(error.UnsupportedMethod, http.parseHead("PUT / HTTP/1.1\r\n"));
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
