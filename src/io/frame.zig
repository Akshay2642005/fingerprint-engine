const std = @import("std");
const Sha256 = std.crypto.hash.sha2.Sha256;

/// FPKG envelope (Design §5): a fixed little-endian header framing every
/// message that crosses the transport boundary. Integrity is a SHA-256 of
/// the payload; versioning lets the worker reject unknown envelopes without
/// parsing them.
pub const magic = [4]u8{ 'F', 'P', 'K', 'G' };

/// Envelope version written by this build of the engine.
pub const current_version: u16 = 1;

/// Total encoded header size in bytes.
pub const header_size = 48;

pub const MessageType = enum(u8) {
    signal_package = 1,
    validation_result = 2,
    normalization_result = 3,
    fingerprint_result = 4,
    risk_result = 5,
    similarity_result = 6,
    diagnostics = 7,
    fingerprint_computed = 8,
};

pub const Codec = enum(u8) {
    binary = 1,
    json = 2,
};

pub const FrameHeader = struct {
    version: u16 = current_version,
    message_type: MessageType,
    codec: Codec,
    payload_len: u32,
    reserved: u32 = 0,
    integrity: [32]u8,

    /// Writes the fixed 48-byte header through `writer` (io.Writer or any
    /// structurally compatible fixed-buffer writer).
    pub fn encode(self: FrameHeader, writer: anytype) !void {
        try writer.writeBytes(&magic);
        try writer.writeInt(u16, self.version);
        try writer.writeInt(u8, @intFromEnum(self.message_type));
        try writer.writeInt(u8, @intFromEnum(self.codec));
        try writer.writeInt(u32, self.payload_len);
        try writer.writeInt(u32, self.reserved);
        try writer.writeBytes(&self.integrity);
    }

    /// Reads and validates a header from `reader`; rejects bad magic,
    /// unsupported versions, and unknown message types/codecs.
    pub fn decode(reader: anytype) !FrameHeader {
        var magic_buf: [4]u8 = undefined;
        try reader.readSlice(&magic_buf);
        if (!std.mem.eql(u8, &magic_buf, &magic)) return error.InvalidMagic;

        const header_version = try reader.readInt(u16);
        if (header_version != current_version) return error.UnsupportedVersion;

        const message_type = try reader.readInt(u8);
        const codec = try reader.readInt(u8);
        const payload_len = try reader.readInt(u32);
        const reserved = try reader.readInt(u32);
        var integrity: [32]u8 = undefined;
        try reader.readSlice(&integrity);

        return FrameHeader{
            .message_type = std.meta.intToEnum(MessageType, message_type) catch
                return error.InvalidMessageType,
            .codec = std.meta.intToEnum(Codec, codec) catch return error.InvalidCodec,
            .payload_len = payload_len,
            .reserved = reserved,
            .integrity = integrity,
        };
    }

    /// SHA-256 digest of a payload — the frame's integrity field.
    pub fn integrityOf(payload: []const u8) [32]u8 {
        var digest: [32]u8 = undefined;
        Sha256.hash(payload, &digest, .{});
        return digest;
    }

    /// True when `header.integrity` matches the SHA-256 of `payload`.
    pub fn integrityValid(header: FrameHeader, payload: []const u8) bool {
        return std.mem.eql(u8, &header.integrity, &integrityOf(payload));
    }
};
