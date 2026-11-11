//! AMQP outbound publisher for the worker (design §7.4, D16).
//!
//! The adapter owns the broker topology: the exchange name, the routing-key
//! scheme, and the message headers. The worker stays transport-agnostic —
//! it only hands whole FPKG reply frames to `publish_reply`, which converts
//! each frame into one published message:
//!
//!   reply frame ──► routing key `result.<message-type>` (kebab-case)
//!               ──► headers: fpkg-message-type, fpkg-envelope-version
//!               ──► body: the complete frame (header + status + engine
//!                   result), so a consumer can verify integrity without
//!                   shared framing code
//!
//! Publisher confirms are enabled on connect, so `publish_reply` blocks
//! until the broker acknowledges the message (or errors). Network failures
//! surface as errors for the worker to log; protocol violations are fatal
//! (`protocol.fatal`), which exits the process for the supervisor to restart.
const std = @import("std");
const stdx = @import("stdx");
const io = @import("io");

const client = @import("client.zig");

/// The result exchange every worker publishes to. Declared durable on
/// connect (idempotent): messages survive broker restarts.
pub const exchange_name = "fingerprint";

/// Dead-letter exchange. Result queues declare with
/// `x-dead-letter-exchange=fingerprint.dlx` so failed/rejected messages
/// route here; the DLQ binds under `dead-letter`.
pub const dlx_name = "fingerprint.dlx";

/// Dead-letter queue. Receives messages from the DLX.
pub const dlq_name = "fingerprint.dlq";

/// Routing key used by the DLQ binding on the DLX.
pub const dlq_routing_key = "dead-letter";

/// Routing key prefix; the full key is `result.<message-type>` so a consumer
/// can bind by exchange topic (`result.*`) or per message type.
const routing_key_prefix = "result.";

/// MIME type of the message body (an FPKG frame is opaque bytes).
const content_type = "application/octet-stream";

/// Generated from the FPKG message-type enum — the wire names can never
/// drift from io/frame.zig tags (data-driven, no switch statements).
const message_types = std.meta.fields(io.frame.MessageType);

/// Kebab-case wire name of a message type, e.g. `fingerprint-result`.
/// The `comptime "" ++` materializes the slice as static data (see
/// stdx.to_case notes).
pub fn messageTypeName(message_type: io.frame.MessageType) []const u8 {
    inline for (message_types) |field| {
        if (message_type == @as(io.frame.MessageType, @enumFromInt(field.value))) {
            return comptime "" ++ stdx.to_case(field.name, .@"kebab-case");
        }
    }
    unreachable;
}

/// Routing key for a message type, e.g. `result.fingerprint-result`.
pub fn routingKey(message_type: io.frame.MessageType) []const u8 {
    inline for (message_types) |field| {
        if (message_type == @as(io.frame.MessageType, @enumFromInt(field.value))) {
            return comptime routing_key_prefix ++ stdx.to_case(field.name, .@"kebab-case");
        }
    }
    unreachable;
}

pub const Options = struct {
    /// Broker address (host:port).
    address: std.net.Address,
    user_name: []const u8,
    password: []const u8,
    virtual_host: []const u8 = "/",
    /// Broker reply deadline for the handshake and publisher confirms (ms).
    reply_timeout_ms: u32 = 5000,
    /// Upper bound on one FPKG reply frame this publisher may send. Must
    /// cover the largest reply the worker can produce
    /// (io.frame.header_size + 1 + worker.max_result).
    message_size_max: u32,
};

pub const Publisher = struct {
    client: client.Client,
    message_size_max: u32,
    options: ?Options = null,
    connected: bool = true,

    /// Connects to the broker, enables publisher confirms, and declares the
    /// result exchange (durable, idempotent). On any failure the socket and
    /// client state are reset and the error is returned, so a supervisor can
    /// retry the whole sequence.
    pub fn init(allocator: std.mem.Allocator, options: Options) !Publisher {
        var c = try client.Client.init(allocator, .{
            .message_count_max = 1,
            .message_body_size_max = options.message_size_max,
            .reply_timeout_ms = options.reply_timeout_ms,
        });
        errdefer c.deinit(allocator);

        try c.connect(.{
            .host = options.address,
            .user_name = options.user_name,
            .password = options.password,
            .vhost = options.virtual_host,
        });
        try c.exchange_declare(.{
            .exchange = exchange_name,
            .type = "direct",
            .passive = false,
            .durable = true,
            .auto_delete = false,
            .internal = false,
        });

        // Dead-letter topology: DLX exchange + DLQ queue bound under
        // `dead-letter`. Result queues (declared by consumers) set
        // `x-dead-letter-exchange=fingerprint.dlx` so failed/rejected
        // messages route here automatically.
        try c.exchange_declare(.{
            .exchange = dlx_name,
            .type = "direct",
            .passive = false,
            .durable = true,
            .auto_delete = false,
            .internal = false,
        });
        try c.queue_declare(.{
            .queue = dlq_name,
            .passive = false,
            .durable = true,
            .exclusive = false,
            .auto_delete = false,
            .arguments = .{},
        });
        try c.queue_bind(.{
            .queue = dlq_name,
            .exchange = dlx_name,
            .routing_key = dlq_routing_key,
            .no_wait = false,
        });
        return .{ .client = c, .message_size_max = options.message_size_max, .options = options };
    }

    pub fn isConnected(self: *const Publisher) bool {
        return self.connected;
    }

    pub fn markDisconnected(self: *Publisher) void {
        self.connected = false;
    }

    /// Replaces a failed broker connection once. The caller owns retry policy;
    /// this method never loops or buffers messages.
    pub fn reconnect(self: *Publisher, allocator: std.mem.Allocator) !void {
        const replacement = try Publisher.init(allocator, self.options orelse return error.NotConnected);
        self.client.abort(allocator);
        self.* = replacement;
    }

    pub fn deinit(self: *Publisher, allocator: std.mem.Allocator) void {
        self.client.deinit(allocator);
    }

    /// Publishes one FPKG reply frame. Blocks until the broker confirms it.
    /// `reply` must be a complete frame (see transport.decodeFrame); only the
    /// header is parsed here — the body is forwarded verbatim.
    /// Returns error.Unroutable if the broker returns basic_return (ADR-016).
    pub fn publish_reply(self: *Publisher, reply: []const u8) !void {
        return self.publish_replyWithRequestId(reply, "");
    }

    pub fn publish_replyWithRequestId(self: *Publisher, reply: []const u8, request_id: []const u8) !void {
        if (reply.len > self.message_size_max) return error.BodyTooLarge;

        // Clear any previous basic_return
        self.client.last_basic_return = false;

        var reader = io.Reader.init(reply);
        const header = try io.frame.FrameHeader.decode(&reader);

        const message = Message{
            .reply = reply,
            .message_type = header.message_type,
            .request_id = request_id,
        };
        self.client.publish(.{
            .exchange = exchange_name,
            .routing_key = routingKey(header.message_type),
            .mandatory = true, // ADR-016: detect unroutable messages
            .immediate = false,
            .properties = .{
                .content_type = content_type,
                .delivery_mode = .persistent,
                .timestamp = @intCast(std.time.timestamp()),
                .headers = message.headers(),
            },
            .body = message.body(),
        }) catch |err| {
            self.connected = false;
            return err;
        };

        // ADR-016: check if basic_return was received
        if (self.client.last_basic_return) {
            return error.Unroutable;
        }
    }

    /// Republishes an unroutable frame to the DLX (ADR-016). Returns error
    /// if the republish also fails; the caller should count it as dlq_failed.
    pub fn republishToDlq(self: *Publisher, frame: []const u8, request_id: []const u8) !void {
        const body = Message{ .reply = frame, .message_type = .diagnostics, .request_id = request_id };
        self.client.publish(.{
            .exchange = dlx_name,
            .routing_key = dlq_routing_key,
            .mandatory = true,
            .immediate = false,
            .properties = .{
                .content_type = content_type,
                .delivery_mode = .persistent,
                .timestamp = @intCast(std.time.timestamp()),
            },
            .body = body.body(),
        }) catch |err| {
            self.connected = false;
            return err;
        };
    }
};

/// One published message: the complete reply frame plus the header metadata
/// derived from its message type. Tight vtable objects write directly into
/// the client's send buffer (no intermediate copies).
const Message = struct {
    reply: []const u8,
    message_type: io.frame.MessageType,
    request_id: []const u8 = "",

    fn body(self: *const Message) client.Encoder.Body {
        const vtable: client.Encoder.Body.VTable = comptime .{
            .write = &struct {
                fn write(context: *const anyopaque, buffer: []u8) usize {
                    const message: *const Message = @ptrCast(@alignCast(context));
                    @memcpy(buffer[0..message.reply.len], message.reply);
                    return message.reply.len;
                }
            }.write,
        };
        return .{ .context = self, .vtable = &vtable };
    }

    fn headers(self: *const Message) client.Encoder.Table {
        const vtable: client.Encoder.Table.VTable = comptime .{
            .write = &struct {
                fn write(context: *const anyopaque, encoder: *client.Encoder.TableEncoder) void {
                    const message: *const Message = @ptrCast(@alignCast(context));
                    encoder.put("fpkg-message-type", .{
                        .string = messageTypeName(message.message_type),
                    });
                    encoder.put("fpkg-envelope-version", .{
                        .uint16 = io.frame.current_version,
                    });
                    if (message.request_id.len > 0) {
                        encoder.put("request_id", .{ .string = message.request_id });
                    }
                }
            }.write,
        };
        return .{ .context = self, .vtable = &vtable };
    }
};
