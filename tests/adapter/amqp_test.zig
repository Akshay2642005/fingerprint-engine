//! AMQP adapter tests: adapter-level behavioral checks plus wire-codec checks
//! that do not require a broker (connection-refused against an unused port).
//!
//! The AMQP client/codec inline unit tests (SendBuffer, ReceiveBuffer,
//! Confirms, frame and property-flags encode/decode) are defined in
//! src/adapter/amqp/ and run standalone, e.g. `zig test src/adapter/amqp/client.zig`.
const std = @import("std");
const stdx = @import("stdx");
const io = @import("io");
const adapter = @import("adapter");
const amqp = adapter.amqp;
const version_info = @import("version");

test "amqp: connection properties carry the injected product version (BUG-002)" {
    // The AMQP handshake advertises the product version; it must match the
    // build's single source of truth, never a hardcoded constant.
    const options = amqp.ConnectOptions{
        .host = try std.net.Address.parseIp("127.0.0.1", 5672),
        .user_name = "guest",
        .password = "guest",
        .vhost = "/",
    };
    try std.testing.expectEqualStrings(version_info.version, options.properties.version);
}

test "amqp: connect to a closed port fails cleanly" {
    // Bind an ephemeral listener, note the port, then close it so the port
    // is guaranteed closed before the client tries to connect.
    const address = std.net.Address.parseIp("127.0.0.1", 0) catch unreachable;
    var stream_server = address.listen(.{ .reuse_address = true }) catch unreachable;
    const port = stream_server.listen_address.getPort();
    stream_server.deinit();

    var client = try amqp.Client.init(std.testing.allocator, .{
        .message_count_max = 8,
        .message_body_size_max = 64 * 1024,
        .reply_timeout_ms = 1000,
    });
    defer client.deinit(std.testing.allocator);

    const options = amqp.ConnectOptions{
        .host = try std.net.Address.parseIp("127.0.0.1", port),
        .user_name = "guest",
        .password = "guest",
        .vhost = "/",
    };
    try std.testing.expectError(error.ConnectionRefused, client.connect(options));
}

test "amqp: to_case kebab maps underscores used in headers" {
    // Header names in the AMQP table use kebab-case; assert the stdx helper
    // agrees with the wire names the codec expects. `to_case` yields a
    // comptime-only slice, so concatenating at comptime materializes it as
    // static data (the production pattern).
    const kebab = comptime "x-" ++ stdx.to_case("message_ttl", .@"kebab-case");
    try std.testing.expectEqualStrings("x-message-ttl", kebab);
}

test "amqp: publisher routing keys are kebab-cased per message type" {
    const publisher = adapter.amqp_publisher;
    try std.testing.expectEqualStrings("result.signal-package", publisher.routingKey(.signal_package));
    try std.testing.expectEqualStrings("result.validation-result", publisher.routingKey(.validation_result));
    try std.testing.expectEqualStrings("result.fingerprint-result", publisher.routingKey(.fingerprint_result));
    try std.testing.expectEqualStrings("result.risk-result", publisher.routingKey(.risk_result));
    try std.testing.expectEqualStrings("result.similarity-result", publisher.routingKey(.similarity_result));
    try std.testing.expectEqualStrings("result.entropy-result", publisher.routingKey(.entropy_result));
    try std.testing.expectEqualStrings("result.diagnostics", publisher.routingKey(.diagnostics));
    try std.testing.expectEqualStrings("result.fingerprint-computed", publisher.routingKey(.fingerprint_computed));
}

test "amqp: publisher header names match the routing key message type" {
    const publisher = adapter.amqp_publisher;
    try std.testing.expectEqualStrings("fingerprint-result", publisher.messageTypeName(.fingerprint_result));
    try std.testing.expectEqualStrings("signal-package", publisher.messageTypeName(.signal_package));
}

test "amqp: publish_reply rejects frames larger than message_size_max" {
    // No broker needed: the size guard must reject before any I/O.
    var client = try amqp.Client.init(std.testing.allocator, .{
        .message_count_max = 1,
        .message_body_size_max = 4096,
        .reply_timeout_ms = 1000,
    });
    defer client.deinit(std.testing.allocator);
    var publisher = adapter.amqp_publisher.Publisher{
        .client = client,
        .message_size_max = 64,
    };

    var frame_buf: [io.frame.header_size + 128]u8 = undefined;
    const frame = try adapter.buildFrame(.fingerprint_result, .binary, &[_]u8{0} ** 128, &frame_buf);
    try std.testing.expectError(error.BodyTooLarge, publisher.publish_reply(frame));
}

test "amqp: push consumer e2e (requires live broker)" {
    // Skip gracefully if no broker is reachable.
    var client = try amqp.Client.init(std.testing.allocator, .{
        .message_count_max = 1,
        .message_body_size_max = io.frame.header_size + (1 << 16),
        .reply_timeout_ms = 2000,
    });
    defer client.deinit(std.testing.allocator);

    const address = std.net.Address.parseIp("127.0.0.1", 5672) catch unreachable;
    client.connect(.{
        .host = address,
        .user_name = "guest",
        .password = "guest",
        .vhost = "/",
    }) catch return; // skip — broker not reachable

    // Declare exchange.
    try client.exchange_declare(.{
        .exchange = adapter.amqp_publisher.exchange_name,
        .type = "direct",
        .passive = false,
        .durable = true,
        .auto_delete = false,
        .internal = false,
    });

    // Declare a throwaway result queue with DLX args (mirrors real topology).
    const queue_name = try std.fmt.allocPrint(std.testing.allocator, "fpkg-consume-test-{x}", .{stdx.unique_u128()});
    defer std.testing.allocator.free(queue_name);
    try client.queue_declare(.{
        .queue = queue_name,
        .passive = false,
        .durable = false,
        .exclusive = true,
        .auto_delete = true,
        .arguments = .{},
    });
    try client.queue_bind(.{
        .queue = queue_name,
        .exchange = adapter.amqp_publisher.exchange_name,
        .routing_key = adapter.amqp_publisher.routingKey(.fingerprint_result),
        .no_wait = false,
    });

    // Set QoS and register consumer.
    try client.qos(.{ .prefetch_count = 1 });
    try client.consume(.{ .queue = queue_name, .no_ack = false });

    // Publish a test frame.
    var frame_buf: [io.frame.header_size + 16]u8 = undefined;
    const test_payload = &[_]u8{ 0, 0xdb, 0x29, 0xfc, 0x13, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A };
    const frame = try adapter.buildFrame(.fingerprint_result, .binary, test_payload, &frame_buf);

    const TestBody = struct {
        data: []const u8,
        fn vtableWrite(context: *const anyopaque, buffer: []u8) usize {
            const self: *const @This() = @ptrCast(@alignCast(context));
            @memcpy(buffer[0..self.data.len], self.data);
            return self.data.len;
        }
        fn body(self: *const @This()) amqp.Encoder.Body {
            return .{ .context = self, .vtable = &.{ .write = &vtableWrite } };
        }
    };
    const test_body = TestBody{ .data = frame };
    try client.publish(.{
        .exchange = adapter.amqp_publisher.exchange_name,
        .routing_key = adapter.amqp_publisher.routingKey(.fingerprint_result),
        .mandatory = false,
        .immediate = false,
        .properties = .{
            .content_type = "application/octet-stream",
            .delivery_mode = .persistent,
        },
        .body = test_body.body(),
    });

    // Receive via push consumer.
    const delivery = try client.consume_next();
    try std.testing.expectEqualStrings(adapter.amqp_publisher.routingKey(.fingerprint_result), delivery.routing_key);
    try std.testing.expectEqualStrings(adapter.amqp_publisher.exchange_name, delivery.exchange);
    try std.testing.expect(!delivery.redelivered);

    const body = try client.consume_body();
    try std.testing.expectEqual(frame.len, body.len);
    try std.testing.expectEqualSlices(u8, frame, body);

    // Ack the delivery.
    try client.consumer_ack(delivery.delivery_tag, false);
}
