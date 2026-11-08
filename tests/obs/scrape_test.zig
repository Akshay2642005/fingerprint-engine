// story: m8-observability
//! Scrape/probe listener tests (ADR-014 §3): the exact HTTP contract the
//! Prometheus scraper and the orchestrator depend on — status codes, content
//! types, the build/readiness preamble, `Connection: close`, GET-only routing,
//! and that a stalled scraper cannot wedge the listener.

const std = @import("std");
const testing = std.testing;
const obs = @import("obs");

const metrics_mod = obs.metrics;
const scrape = obs.scrape;

const TestRegistry = struct {
    requests_total: metrics_mod.Counter() = .{},
};

const Fixture = struct {
    registry: TestRegistry = .{},
    ready: std.atomic.Value(bool) = std.atomic.Value(bool).init(true),
    dependency: []const u8 = "worker_pool",

    fn renderMetrics(context: *anyopaque, writer: std.io.AnyWriter) anyerror!void {
        const self: *Fixture = @ptrCast(@alignCast(context));
        try metrics_mod.render("fpkg_test_", &self.registry, writer);
    }

    fn isReady(context: *anyopaque) ?[]const u8 {
        const self: *Fixture = @ptrCast(@alignCast(context));
        return if (self.ready.load(.acquire)) null else self.dependency;
    }
};

fn startServer(fixture: *Fixture, head_timeout_ns: u64, server: *scrape.Server) !void {
    server.* = try scrape.listen(.{
        .address = try std.net.Address.parseIp("127.0.0.1", 0),
        .component = "test",
        .version = "0.7.0",
        .metrics_context = fixture,
        .render_metrics = Fixture.renderMetrics,
        .ready_context = fixture,
        .is_ready = Fixture.isReady,
        .head_timeout_ns = head_timeout_ns,
    });
    errdefer server.server.deinit();
    try server.start();
}

/// Opens one connection, writes `request`, and reads until the server closes
/// (`Connection: close`). The caller owns the returned bytes.
fn request(allocator: std.mem.Allocator, server: *const scrape.Server, payload: []const u8) ![]u8 {
    const stream = try std.net.tcpConnectToAddress(server.server.listen_address);
    defer stream.close();
    try stream.writeAll(payload);

    var response = std.ArrayList(u8).init(allocator);
    errdefer response.deinit();
    var buffer: [4096]u8 = undefined;
    while (true) {
        const n = try stream.read(&buffer);
        if (n == 0) break;
        try response.appendSlice(buffer[0..n]);
    }
    return response.toOwnedSlice();
}

fn bodyOf(raw: []const u8) []const u8 {
    const end = std.mem.indexOf(u8, raw, "\r\n\r\n") orelse return "";
    return raw[end + 4 ..];
}

fn expectBodyEquals(expected: []const u8, raw: []const u8) !void {
    try testing.expectEqualStrings(expected, bodyOf(raw));
}

test "scrape: /metrics serves build info, readiness, and the registry" {
    var fixture = Fixture{};
    fixture.registry.requests_total.inc();
    var server: scrape.Server = undefined;
    try startServer(&fixture, scrape.default_head_timeout_ns, &server);
    defer server.stop();

    const raw = try request(testing.allocator, &server, "GET /metrics HTTP/1.1\r\nHost: test\r\n\r\n");
    defer testing.allocator.free(raw);

    try testing.expect(std.mem.startsWith(u8, raw, "HTTP/1.1 200 OK\r\n"));
    try testing.expect(std.mem.indexOf(u8, raw, "Content-Type: text/plain; version=0.0.4; charset=utf-8\r\n") != null);
    try testing.expect(std.mem.indexOf(u8, raw, "Connection: close\r\n") != null);
    try testing.expect(std.mem.indexOf(u8, raw, "fpkg_test_build_info{version=\"0.7.0\"} 1\n") != null);
    try testing.expect(std.mem.indexOf(u8, raw, "fpkg_test_ready 1\n") != null);
    try testing.expect(std.mem.indexOf(u8, raw, "# TYPE fpkg_test_requests_total counter\n") != null);
    try testing.expect(std.mem.indexOf(u8, raw, "fpkg_test_requests_total 1\n") != null);
}

test "scrape: /readyz reports readiness and names the failing dependency" {
    var fixture = Fixture{};
    var server: scrape.Server = undefined;
    try startServer(&fixture, scrape.default_head_timeout_ns, &server);
    defer server.stop();

    const ready = try request(testing.allocator, &server, "GET /readyz HTTP/1.1\r\n\r\n");
    defer testing.allocator.free(ready);
    try testing.expect(std.mem.startsWith(u8, ready, "HTTP/1.1 200 OK\r\n"));
    try expectBodyEquals("{\"ready\":true,\"component\":\"test\",\"version\":\"0.7.0\"}", ready);

    fixture.ready.store(false, .release);

    const unready = try request(testing.allocator, &server, "GET /readyz HTTP/1.1\r\n\r\n");
    defer testing.allocator.free(unready);
    try testing.expect(std.mem.startsWith(u8, unready, "HTTP/1.1 503 Service Unavailable\r\n"));
    try expectBodyEquals("{\"ready\":false,\"component\":\"test\",\"dependency\":\"worker_pool\"}", unready);

    // The metrics preamble must agree with the probe.
    const scraped = try request(testing.allocator, &server, "GET /metrics HTTP/1.1\r\n\r\n");
    defer testing.allocator.free(scraped);
    try testing.expect(std.mem.indexOf(u8, scraped, "fpkg_test_ready 0\n") != null);
}

test "scrape: non-GET is 405 with an Allow header" {
    var fixture = Fixture{};
    var server: scrape.Server = undefined;
    try startServer(&fixture, scrape.default_head_timeout_ns, &server);
    defer server.stop();

    const raw = try request(testing.allocator, &server, "POST /metrics HTTP/1.1\r\nContent-Length: 0\r\n\r\n");
    defer testing.allocator.free(raw);

    try testing.expect(std.mem.startsWith(u8, raw, "HTTP/1.1 405 Method Not Allowed\r\n"));
    try testing.expect(std.mem.indexOf(u8, raw, "Allow: GET\r\n") != null);
    try expectBodyEquals("{\"error\":\"method not allowed\"}", raw);
}

test "scrape: unknown paths are 404 (liveness stays on the API port)" {
    var fixture = Fixture{};
    var server: scrape.Server = undefined;
    try startServer(&fixture, scrape.default_head_timeout_ns, &server);
    defer server.stop();

    const raw = try request(testing.allocator, &server, "GET /healthz HTTP/1.1\r\n\r\n");
    defer testing.allocator.free(raw);

    try testing.expect(std.mem.startsWith(u8, raw, "HTTP/1.1 404 Not Found\r\n"));
    try expectBodyEquals("{\"error\":\"not found\"}", raw);
}

test "scrape: query strings are ignored" {
    var fixture = Fixture{};
    var server: scrape.Server = undefined;
    try startServer(&fixture, scrape.default_head_timeout_ns, &server);
    defer server.stop();

    const raw = try request(testing.allocator, &server, "GET /metrics?target=all HTTP/1.1\r\n\r\n");
    defer testing.allocator.free(raw);

    try testing.expect(std.mem.startsWith(u8, raw, "HTTP/1.1 200 OK\r\n"));
    try testing.expect(std.mem.indexOf(u8, raw, "fpkg_test_build_info") != null);
}

test "scrape: a stalled client times out and the listener keeps serving" {
    var fixture = Fixture{};
    var server: scrape.Server = undefined;
    try startServer(&fixture, 100 * std.time.ns_per_ms, &server);
    defer server.stop();

    // Connect and send nothing. The head budget must expire.
    const stalled = try std.net.tcpConnectToAddress(server.server.listen_address);
    defer stalled.close();

    var buffer: [256]u8 = undefined;
    const n = try stalled.read(&buffer);
    try testing.expect(n > 0);
    try testing.expect(std.mem.startsWith(u8, buffer[0..n], "HTTP/1.1 408 Request Timeout\r\n"));

    // A subsequent scrape is unaffected.
    const raw = try request(testing.allocator, &server, "GET /metrics HTTP/1.1\r\n\r\n");
    defer testing.allocator.free(raw);
    try testing.expect(std.mem.startsWith(u8, raw, "HTTP/1.1 200 OK\r\n"));
}

test "scrape: a partial head that never terminates is also timed out" {
    var fixture = Fixture{};
    var server: scrape.Server = undefined;
    try startServer(&fixture, 100 * std.time.ns_per_ms, &server);
    defer server.stop();

    const slow = try std.net.tcpConnectToAddress(server.server.listen_address);
    defer slow.close();
    try slow.writeAll("GET /met");

    var buffer: [256]u8 = undefined;
    const n = try slow.read(&buffer);
    try testing.expect(n > 0);
    try testing.expect(std.mem.startsWith(u8, buffer[0..n], "HTTP/1.1 408 Request Timeout\r\n"));
}

test "scrape: parseAddress handles any, IPv4, and bracketed IPv6" {
    var address = try scrape.parseAddress(testing.allocator, ":9090");
    try testing.expectEqual(@as(u16, 9090), address.getPort());
    try testing.expectEqual(std.posix.AF.INET, address.any.family);

    address = try scrape.parseAddress(testing.allocator, "127.0.0.1:9091");
    try testing.expectEqual(@as(u16, 9091), address.getPort());
    try testing.expectEqual(@as(u8, 127), address.in.sa.addr & 0xff);

    address = try scrape.parseAddress(testing.allocator, "[::1]:9092");
    try testing.expectEqual(@as(u16, 9092), address.getPort());
    try testing.expectEqual(std.posix.AF.INET6, address.any.family);

    try testing.expectError(error.InvalidAddress, scrape.parseAddress(testing.allocator, "nonsense"));
    try testing.expectError(error.InvalidAddress, scrape.parseAddress(testing.allocator, "host:"));
    try testing.expectError(error.InvalidAddress, scrape.parseAddress(testing.allocator, "host:port"));
}
