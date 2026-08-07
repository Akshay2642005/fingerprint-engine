/// TCP request/response transport (design §7.3, D16): an FPKG-framed
/// server for the ingress → worker inbound path. One client at a time;
/// the worker drives `accept → readFrame → process → writeFrame` and this
/// type owns only the socket state. Frames are read with `readFrameFrom`,
/// so integrity is validated at the boundary.
const std = @import("std");
const transport = @import("transport.zig");

pub const Tcp = struct {
    allocator: std.mem.Allocator,
    server: std.net.Server,
    client: ?std.net.Stream = null,

    pub fn init(allocator: std.mem.Allocator, host: []const u8, port_number: u16) !Tcp {
        const address = try std.net.Address.parseIp(host, port_number);
        const server = try address.listen(.{ .reuse_address = true });
        return .{ .allocator = allocator, .server = server };
    }

    pub fn deinit(self: *Tcp) void {
        if (self.client) |client| client.close();
        self.server.deinit();
    }

    /// The bound port; useful when the caller asked for port 0.
    pub fn port(self: *const Tcp) u16 {
        return self.server.listen_address.getPort();
    }

    /// Blocks until a client connects. A previous client, if any, is closed
    /// first — the transport serves one connection at a time.
    pub fn accept(self: *Tcp) !void {
        const connection = try self.server.accept();
        if (self.client) |client| client.close();
        self.client = connection.stream;
    }

    /// One inbound FPKG frame from the accepted client; memory is owned by
    /// the caller.
    pub fn readFrame(self: *Tcp, allocator: std.mem.Allocator) ![]const u8 {
        const client = self.client orelse return error.NotConnected;
        return transport.readFrameFrom(client.reader(), allocator);
    }

    pub fn writeFrame(self: *Tcp, frame: []const u8) !void {
        const client = self.client orelse return error.NotConnected;
        try client.writer().writeAll(frame);
    }

    /// Outbound events are a v1 no-op for tcp (no downstream consumer).
    pub fn publish(self: *Tcp, payload: []const u8) !void {
        _ = self;
        _ = payload;
    }

    /// Poison-frame handling is a v1 no-op for tcp.
    pub fn ack(self: *Tcp, frame: []const u8) void {
        _ = self;
        _ = frame;
    }
};

comptime {
    transport.check(Tcp);
}
