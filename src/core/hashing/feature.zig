const std = @import("std");
const fingerprint = @import("../fingerprint/root.zig");

const FeatureValue = fingerprint.FeatureValue;
const Sha256 = std.crypto.hash.sha2.Sha256;

/// Type tag byte written before value data when hashing.
/// Ensures different FeatureType variants never collide.
const TAG_BOOLEAN: u8 = 0x01;
const TAG_INTEGER: u8 = 0x02;
const TAG_FLOAT: u8 = 0x03;
const TAG_STRING: u8 = 0x04;
const TAG_BYTES: u8 = 0x05;
const TAG_STRING_ARRAY: u8 = 0x06;
const TAG_INTEGER_ARRAY: u8 = 0x07;
const TAG_FLOAT_ARRAY: u8 = 0x08;
const TAG_BYTES_ARRAY: u8 = 0x09;

/// Hashes a single FeatureValue to a 32-byte SHA-256 digest.
/// The hash is deterministic: same value → same digest every time.
pub fn hashFeature(value: FeatureValue, out: *[32]u8) !void {
    var ctx = Sha256.init(.{});
    switch (value) {
        .Boolean => |v| {
            ctx.update(&[_]u8{ TAG_BOOLEAN });
            ctx.update(&[_]u8{ if (v) 1 else 0 });
        },
        .Integer => |v| {
            ctx.update(&[_]u8{ TAG_INTEGER });
            var buf: [8]u8 = undefined;
            std.mem.writeInt(i64, &buf, v, .little);
            ctx.update(&buf);
        },
        .Float => |v| {
            ctx.update(&[_]u8{ TAG_FLOAT });
            var buf: [8]u8 = undefined;
            std.mem.writeInt(u64, &buf, @bitCast(v), .little);
            ctx.update(&buf);
        },
        .String => |v| {
            ctx.update(&[_]u8{ TAG_STRING });
            var len_buf: [4]u8 = undefined;
            std.mem.writeInt(u32, &len_buf, @as(u32, @intCast(v.len)), .little);
            ctx.update(&len_buf);
            ctx.update(v);
        },
        .Bytes => |v| {
            ctx.update(&[_]u8{ TAG_BYTES });
            var len_buf: [4]u8 = undefined;
            std.mem.writeInt(u32, &len_buf, @as(u32, @intCast(v.len)), .little);
            ctx.update(&len_buf);
            ctx.update(v);
        },
        .StringArray => |v| {
            ctx.update(&[_]u8{ TAG_STRING_ARRAY });
            var count_buf: [4]u8 = undefined;
            std.mem.writeInt(u32, &count_buf, @as(u32, @intCast(v.len)), .little);
            ctx.update(&count_buf);
            for (v) |item| {
                var len_buf: [4]u8 = undefined;
                std.mem.writeInt(u32, &len_buf, @as(u32, @intCast(item.len)), .little);
                ctx.update(&len_buf);
                ctx.update(item);
            }
        },
        .IntegerArray => |v| {
            ctx.update(&[_]u8{ TAG_INTEGER_ARRAY });
            var count_buf: [4]u8 = undefined;
            std.mem.writeInt(u32, &count_buf, @as(u32, @intCast(v.len)), .little);
            ctx.update(&count_buf);
            for (v) |item| {
                var buf: [8]u8 = undefined;
                std.mem.writeInt(i64, &buf, item, .little);
                ctx.update(&buf);
            }
        },
        .FloatArray => |v| {
            ctx.update(&[_]u8{ TAG_FLOAT_ARRAY });
            var count_buf: [4]u8 = undefined;
            std.mem.writeInt(u32, &count_buf, @as(u32, @intCast(v.len)), .little);
            ctx.update(&count_buf);
            for (v) |item| {
                var buf: [8]u8 = undefined;
                std.mem.writeInt(u64, &buf, @bitCast(item), .little);
                ctx.update(&buf);
            }
        },
        .BytesArray => |v| {
            ctx.update(&[_]u8{ TAG_BYTES_ARRAY });
            var count_buf: [4]u8 = undefined;
            std.mem.writeInt(u32, &count_buf, @as(u32, @intCast(v.len)), .little);
            ctx.update(&count_buf);
            for (v) |item| {
                var len_buf: [4]u8 = undefined;
                std.mem.writeInt(u32, &len_buf, @as(u32, @intCast(item.len)), .little);
                ctx.update(&len_buf);
                ctx.update(item);
            }
        },
    }
    ctx.final(out);
}
