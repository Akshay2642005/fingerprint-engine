//! Grab bag of automation scripts around Fingerprint Engine.
//!
//! Design rationale:
//! - Bash is not cross platform, suffers from high accidental complexity, and
//!   is a second language. We strive to centralize on Zig for all of the things.
//! - While build.zig is great for _building_ software using a graph of tasks
//!   with dependency tracking, higher-level orchestration is easier if you
//!   just write direct imperative code.
//! - To minimize the number of things that need compiling and improve link
//!   times, all scripts are subcommands of a single binary.
//!
//!   This is a special case of the following rule-of-thumb: length of
//!   `build.zig` should be O(1).
const std = @import("std");
const model = @import("model");
const serialization = @import("serialization");
const engine = @import("engine");
const io = @import("io");
const adapter = @import("adapter");
const stdx = @import("stdx");

const usage =
    \\Usage:
    \\
    \\  zig build scripts -- [-h | --help]
    \\
    \\  zig build scripts -- help
    \\
    \\  zig build scripts -- generate fixture <name>
    \\    Write a canonical test fixture under tests/fixtures/ and print the
    \\    engine's hash of it — the digest the worker e2e tests pin as a
    \\    compile-time constant. Run from the repository root.
    \\
    \\  zig build scripts -- docker build-worker [--tag=name]
    \\    Build the worker container image (deploy/Dockerfile.worker);
    \\    defaults to the fingerprint-worker:0.2.0 tag.
    \\
    \\  zig build scripts -- docker run [--tag=name]
    \\    Run the worker image in the foreground, publishing port 8080.
    \\
    \\  zig build scripts -- worker request [--listen=host:port]
    \\    Send the canonical signal package fixture to a running worker
    \\    (default 127.0.0.1:8080 — point it at the container's published
    \\    port) and print the reply: status, digest (cross-checked against
    \\    an in-process engine call), feature count, schema version.
    \\
    \\  zig build scripts -- amqp [--address=host:port]
    \\    Live AMQP smoke test against a broker (default 127.0.0.1:5672):
    \\    declare the fingerprint exchange, bind a throwaway queue to it,
    \\    publish a reply frame through the worker publisher, and verify it
    \\    round-trips back out of the broker. Requires a reachable RabbitMQ.
    \\
;

/// Fixture packages are defined here, in the same model code the engine
/// uses, so the bytes can never drift from what the worker actually hashes.
const fixtures = .{
    .signal_package_v2 = struct {
        const name = "signal-package-v2";
        const path = "tests/fixtures/fingerprints/signal-package-v2.bin";

        const package_id = [16]u8{
            0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
            0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10,
        };

        fn fingerprint() model.Fingerprint {
            return .{
                .metadata = .{
                    .schema_version = serialization.schema_version_v2,
                    .sdk_version = "0.2.0",
                    .collected_at = 1700000000123,
                    .package_id = package_id,
                },
                .features = &.{
                    model.Feature{ .id = model.FeatureID.UserAgent, .value = .{ .String = "Mozilla/5.0" } },
                    model.Feature{ .id = model.FeatureID.CookieEnabled, .value = .{ .Boolean = true } },
                    model.Feature{ .id = model.FeatureID.HardwareConcurrency, .value = .{ .Integer = 8 } },
                },
            };
        }
    },
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    const subcommand = if (args.len > 1) args[1] else "help";
    if (std.mem.eql(u8, subcommand, "help") or
        std.mem.eql(u8, subcommand, "-h") or
        std.mem.eql(u8, subcommand, "--help"))
    {
        try std.io.getStdOut().writer().writeAll(usage);
        return;
    }

    if (std.mem.eql(u8, subcommand, "generate")) {
        try generate(alloc, args);
        return;
    }

    if (std.mem.eql(u8, subcommand, "docker")) {
        try dockerCommand(alloc, args);
        return;
    }

    if (std.mem.eql(u8, subcommand, "worker")) {
        try workerCommand(alloc, args);
        return;
    }

    if (std.mem.eql(u8, subcommand, "amqp")) {
        try amqpCommand(alloc, args);
        return;
    }

    std.debug.print("unknown subcommand '{s}'\n\n{s}", .{ subcommand, usage });
    std.process.exit(1);
}

/// Default image tag, matching `zig build docker:worker`.
const default_tag = "fingerprint-worker:0.2.0";

/// docker build-worker [--tag=name] / docker run [--tag=name]. Child stdio
/// is inherited so docker's own progress and interactive output flow through.
fn dockerCommand(alloc: std.mem.Allocator, args: []const []const u8) !void {
    const sub = if (args.len > 2) args[2] else "";
    var tag: []const u8 = default_tag;
    if (args.len > 3) {
        for (args[3..]) |arg| {
            if (std.mem.startsWith(u8, arg, "--tag=")) {
                tag = arg["--tag=".len..];
            } else {
                std.debug.print("docker: unknown option '{s}'\n\n{s}", .{ arg, usage });
                std.process.exit(1);
            }
        }
    }

    if (std.mem.eql(u8, sub, "build-worker")) {
        try runChild(alloc, &.{ "docker", "build", "-f", "deploy/Dockerfile.worker", "-t", tag, "." });
        try std.io.getStdOut().writer().print("built {s}\n", .{tag});
    } else if (std.mem.eql(u8, sub, "run")) {
        try runChild(alloc, &.{ "docker", "run", "--rm", "-p", "8080:8080", tag });
    } else {
        std.debug.print("docker: expected build-worker or run\n\n{s}", .{usage});
        std.process.exit(1);
    }
}

/// Spawns `argv` with inherited stdio and exits with its status.
fn runChild(alloc: std.mem.Allocator, argv: []const []const u8) !void {
    var child = std.process.Child.init(argv, alloc);
    child.spawn() catch {
        std.debug.print("docker: failed to launch docker (is it installed and running?)\n", .{});
        std.process.exit(1);
    };
    const term = try child.wait();
    switch (term) {
        .Exited => |code| if (code != 0) std.process.exit(code),
        else => std.process.exit(1),
    }
}

/// worker request [--listen=host:port] — one FPKG round-trip against a
/// running worker. The request wraps the canonical signal package fixture;
/// the reply's digest is cross-checked against an in-process engine call so
/// a mismatch means the worker binary drifted, not that framing changed.
fn workerCommand(alloc: std.mem.Allocator, args: []const []const u8) !void {
    const sub = if (args.len > 2) args[2] else "";
    if (!std.mem.eql(u8, sub, "request")) {
        std.debug.print("worker: expected 'request'\n\n{s}", .{usage});
        std.process.exit(1);
    }
    var listen: []const u8 = "127.0.0.1:8080";
    if (args.len > 3) {
        for (args[3..]) |arg| {
            if (std.mem.startsWith(u8, arg, "--listen=")) {
                listen = arg["--listen=".len..];
            } else {
                std.debug.print("worker: unknown option '{s}'\n\n{s}", .{ arg, usage });
                std.process.exit(1);
            }
        }
    }
    const colon = std.mem.lastIndexOfScalar(u8, listen, ':') orelse {
        std.debug.print("worker: invalid --listen '{s}' (expected host:port)\n", .{listen});
        std.process.exit(1);
    };
    const host = listen[0..colon];
    const port = std.fmt.parseInt(u16, listen[colon + 1 ..], 10) catch {
        std.debug.print("worker: invalid port in --listen '{s}'\n", .{listen});
        std.process.exit(1);
    };

    const F = fixtures.signal_package_v2;
    const payload = try std.fs.cwd().readFileAlloc(alloc, F.path, 1 << 16);
    defer alloc.free(payload);

    var frame_buf: [io.frame.header_size + 1 << 16]u8 = undefined;
    const frame = try buildRequestFrame(payload, &frame_buf);

    var stream = std.net.tcpConnectToHost(alloc, host, port) catch {
        std.debug.print("worker: could not connect to {s} (is the worker running?)\n", .{listen});
        std.process.exit(1);
    };
    defer stream.close();
    try stream.writeAll(frame);

    var reply_buf: [io.frame.header_size + 1 << 16]u8 = undefined;
    const reply = try readReplyFrame(stream.reader(), &reply_buf);

    const stdout = std.io.getStdOut().writer();
    var header_buf: [io.frame.header_size]u8 = undefined;
    @memcpy(&header_buf, reply[0..io.frame.header_size]);
    var header_reader = io.Reader.init(&header_buf);
    const header = try io.frame.FrameHeader.decode(&header_reader);
    const reply_payload = reply[io.frame.header_size..];
    if (reply_payload.len < 1) return error.Truncated;

    const status = std.meta.intToEnum(engine.Status, reply_payload[0]) catch {
        try stdout.print("reply: message_type={s} status=invalid byte {d}\n", .{ @tagName(header.message_type), reply_payload[0] });
        std.process.exit(1);
    };
    try stdout.print("message_type: {s}\n", .{@tagName(header.message_type)});
    try stdout.print("status:       {s}\n", .{@tagName(status)});
    if (status != .ok or reply_payload.len < 33) return;

    // Independent reference: the same engine call the worker performs.
    var result_buf: [128]u8 = undefined;
    var response = engine.Response.init(.hash, &result_buf);
    var request = engine.Request{ .operation = .hash, .codec = .binary, .payload = payload };
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    try engine.process(&request, &response, arena.allocator());
    const expected = if (response.status == .ok) response.slice()[0..32] else null;

    const got = reply_payload[1..33];
    if (expected) |want| {
        if (std.mem.eql(u8, want, got)) {
            try stdout.print("digest:       {s} (matches local engine)\n", .{std.fmt.bytesToHex(got, .lower)});
        } else {
            try stdout.print("digest MISMATCH: worker={s} local={s}\n", .{
                std.fmt.bytesToHex(got, .lower),
                std.fmt.bytesToHex(want, .lower),
            });
            std.process.exit(1);
        }
    } else {
        try stdout.print("digest:       {s} (local reference unavailable)\n", .{std.fmt.bytesToHex(got, .lower)});
    }
    if (reply_payload.len >= 37) {
        try stdout.print("features:     {d}\n", .{std.mem.readInt(u16, reply_payload[33..35], .little)});
        try stdout.print("schema:       {d}\n", .{std.mem.readInt(u16, reply_payload[35..37], .little)});
    }
}

/// Wraps `payload` in an FPKG request frame (signal_package, binary codec).
fn buildRequestFrame(payload: []const u8, buf: []u8) ![]const u8 {
    const header = io.frame.FrameHeader{
        .message_type = .signal_package,
        .codec = .binary,
        .payload_len = @intCast(payload.len),
        .integrity = io.frame.FrameHeader.integrityOf(payload),
    };
    var w = io.Writer.init(buf);
    try header.encode(&w);
    @memcpy(buf[io.frame.header_size .. io.frame.header_size + payload.len], payload);
    return buf[0 .. io.frame.header_size + payload.len];
}

/// Reads one FPKG frame from the stream and validates header + integrity.
fn readReplyFrame(reader: anytype, buf: []u8) ![]const u8 {
    var header_buf: [io.frame.header_size]u8 = undefined;
    try reader.readNoEof(&header_buf);
    var header_reader = io.Reader.init(&header_buf);
    const header = try io.frame.FrameHeader.decode(&header_reader);
    const total = io.frame.header_size + header.payload_len;
    if (total > buf.len) return error.FrameTooLarge;
    @memcpy(buf[0..io.frame.header_size], &header_buf);
    try reader.readNoEof(buf[io.frame.header_size..total]);
    if (!header.integrityValid(buf[io.frame.header_size..total])) return error.IntegrityMismatch;
    return buf[0..total];
}

/// amqp [--address=host:port] — live broker smoke test. Declares the
/// fingerprint exchange (idempotent), binds a throwaway queue to it, pushes
/// a reply frame through the worker publisher, and verifies it round-trips
/// back out of the broker. Prints PASS and exits 0 on success.
fn amqpCommand(alloc: std.mem.Allocator, args: []const []const u8) !void {
    var address: []const u8 = "127.0.0.1:5672";
    if (args.len > 2) {
        for (args[2..]) |arg| {
            if (std.mem.startsWith(u8, arg, "--address=")) {
                address = arg["--address=".len..];
            } else {
                std.debug.print("amqp: unknown option '{s}'\n\n{s}", .{ arg, usage });
                std.process.exit(1);
            }
        }
    }
    const colon = std.mem.lastIndexOfScalar(u8, address, ':') orelse {
        std.debug.print("amqp: invalid --address '{s}' (expected host:port)\n", .{address});
        std.process.exit(1);
    };
    const host = address[0..colon];
    const port = std.fmt.parseInt(u16, address[colon + 1 ..], 10) catch {
        std.debug.print("amqp: invalid port in --address '{s}'\n", .{address});
        std.process.exit(1);
    };
    const parsed = std.net.Address.parseIp(host, port) catch {
        std.debug.print("amqp: invalid --address '{s}' (expected host:port)\n", .{address});
        std.process.exit(1);
    };

    const stdout = std.io.getStdOut().writer();

    // The worker publisher: connects, enables confirms, declares the exchange.
    var publisher = adapter.amqp_publisher.Publisher.init(alloc, .{
        .address = parsed,
        .user_name = "guest",
        .password = "guest",
        .virtual_host = "/",
        .message_size_max = io.frame.header_size + (1 << 16),
    }) catch |err| {
        std.debug.print("amqp: connect failed: {s} (is RabbitMQ running at {s}?)\n", .{ @errorName(err), address });
        std.process.exit(1);
    };
    defer publisher.deinit(alloc);
    try stdout.print("connected to {s}; exchange '{s}' declared\n", .{ address, adapter.amqp_publisher.exchange_name });

    // Throwaway queue bound to every result routing key.
    const queue_name = try std.fmt.allocPrint(alloc, "fpkg-test-{x}", .{stdx.unique_u128()});
    defer alloc.free(queue_name);
    try publisher.client.queue_declare(.{
        .queue = queue_name,
        .passive = false,
        .durable = false,
        .exclusive = true,
        .auto_delete = true,
        .arguments = .{},
    });
    try publisher.client.queue_bind(.{
        .queue = queue_name,
        .exchange = adapter.amqp_publisher.exchange_name,
        // Direct exchange: bind the exact key of the message we publish below.
        .routing_key = adapter.amqp_publisher.routingKey(.fingerprint_result),
        .no_wait = false,
    });
    try stdout.print("queue '{s}' bound to {s}\n", .{ queue_name, adapter.amqp_publisher.routingKey(.fingerprint_result) });

    // Publish a reply frame exactly as the worker would (fingerprint_result).
    const payload = &[_]u8{ 0, 0xdb, 0x29, 0xfc, 0x13 }; // status ok + digest head
    var frame_buf: [io.frame.header_size + 16]u8 = undefined;
    const frame = try adapter.buildFrame(.fingerprint_result, .binary, payload, &frame_buf);
    try publisher.publish_reply(frame);
    try stdout.print("published {d} bytes under result.fingerprint-result\n", .{frame.len});

    // Read it back and compare byte-for-byte.
    const message = try publisher.client.get_message(.{ .queue = queue_name, .no_ack = false });
    const message_info = message orelse {
        std.debug.print("amqp: FAIL — queue empty after publish\n", .{});
        std.process.exit(1);
    };
    const body = try publisher.client.get_message_body();
    defer publisher.client.nack(.{
        .delivery_tag = message_info.delivery_tag,
        .requeue = false,
        .multiple = false,
    }) catch {};

    if (!std.mem.eql(u8, body, frame)) {
        std.debug.print("amqp: FAIL — body mismatch ({d} != {d} bytes)\n", .{ body.len, frame.len });
        std.process.exit(1);
    }
    try stdout.print("amqp: PASS — {d} bytes round-tripped identically\n", .{body.len});
}

fn generate(alloc: std.mem.Allocator, args: []const []const u8) !void {
    const name = if (args.len > 2) args[2] else "";
    if (!std.mem.eql(u8, name, "fixture") or args.len < 4) {
        std.debug.print("usage: zig build scripts -- generate fixture <name>\n", .{});
        std.process.exit(1);
    }
    const fixture_name = args[3];
    if (std.mem.eql(u8, fixture_name, fixtures.signal_package_v2.name)) {
        return generateSignalPackageV2(alloc);
    }
    std.debug.print("unknown fixture '{s}'\n\n{s}", .{ fixture_name, usage });
    std.process.exit(1);
}

/// Serializes the canonical v2 signal package, writes it under
/// tests/fixtures/, and prints its engine hash.
fn generateSignalPackageV2(alloc: std.mem.Allocator) !void {
    const F = fixtures.signal_package_v2;
    const fp = F.fingerprint();

    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try serialization.encode(fbs.writer(), fp);
    const bytes = fbs.getWritten();

    var file = try std.fs.cwd().createFile(F.path, .{});
    defer file.close();
    try file.writeAll(bytes);

    var result_buf: [128]u8 = undefined;
    var response = engine.Response.init(.hash, &result_buf);
    var request = engine.Request{ .operation = .hash, .codec = .binary, .payload = bytes };
    // The engine decodes the package into scratch; an arena contains the
    // allocations, matching the worker's service loop.
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    try engine.process(&request, &response, arena.allocator());

    const stdout = std.io.getStdOut().writer();
    try stdout.print("wrote {s} ({d} bytes)\n", .{ F.path, bytes.len });
    if (response.status != .ok) {
        try stdout.print("hash failed: {s}\n", .{@tagName(response.status)});
        std.process.exit(1);
    }
    try stdout.print("digest: {s}\n", .{std.fmt.bytesToHex(response.slice()[0..32], .lower)});
}
