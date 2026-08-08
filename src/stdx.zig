//! Shared low-level utilities (leaf module: depends on nothing but std).
//!
//! These are the helpers the AMQP codec and client use: memory copy helpers
//! with strict overlap/size invariants, fixed-capacity bitsets, a
//! deterministic test PRNG, and small string/conversion helpers. The set is
//! intentionally small — add helpers here only when more than one subsystem
//! needs them.
const std = @import("std");
const assert = std.debug.assert;

pub const KiB = 1 << 10;

/// Asserts that `ok` is true in Debug builds; a no-op in Release.
/// Documents that either value is acceptable; never fails.
/// Unlike `assert`, this does not check a condition.
pub fn maybe(ok: bool) void {
    assert(ok or !ok);
}

pub const SizePrecision = enum { exact, inexact };

pub inline fn copy_left(
    comptime precision: SizePrecision,
    comptime T: type,
    target: []T,
    source: []const T,
) void {
    switch (precision) {
        .exact => assert(target.len == source.len),
        .inexact => assert(target.len >= source.len),
    }

    if (!disjoint_slices(T, T, target, source)) {
        assert(@intFromPtr(target.ptr) < @intFromPtr(source.ptr));
    }

    // (Bypass tidy's ban.)
    const copyForwards = std.mem.copyForwards;
    copyForwards(T, target, source);
}

pub inline fn copy_disjoint(
    comptime precision: SizePrecision,
    comptime T: type,
    target: []T,
    source: []const T,
) void {
    switch (precision) {
        .exact => assert(target.len == source.len),
        .inexact => assert(target.len >= source.len),
    }

    // disjoint_slices() doesn't work in comptime, because of limitations with @intFromPtr:
    // https://github.com/ziglang/zig/issues/23072.
    assert(!@inComptime());
    assert(disjoint_slices(T, T, target, source));

    @memcpy // Bypass tidy ban.
    (target[0..source.len], source);
}

pub inline fn disjoint_slices(comptime A: type, comptime B: type, a: []const A, b: []const B) bool {
    return @intFromPtr(a.ptr) + a.len * @sizeOf(A) <= @intFromPtr(b.ptr) or
        @intFromPtr(b.ptr) + b.len * @sizeOf(B) <= @intFromPtr(a.ptr);
}

/// Checks that a byteslice is zeroed.
pub fn zeroed(bytes: []const u8) bool {
    var byte_bits: u8 = 0;
    for (bytes) |byte| {
        byte_bits |= byte;
    }
    return byte_bits == 0;
}

pub fn unique_u128() u128 {
    const value = std.crypto.random.int(u128);

    // Broken CSPRNG is the likeliest explanation for zero or all ones.
    assert(value != 0);
    assert(value != std.math.maxInt(u128));

    return value;
}

/// Converts a `snake_case` identifier to another casing at comptime
/// (used to derive AMQP table argument names like "x-message-ttl").
pub fn to_case(
    comptime snake_case: []const u8,
    comptime case: enum { camelCase, @"kebab-case", PascalCase, UPPER_CASE },
) []const u8 {
    return comptime blk: {
        var output: [snake_case.len]u8 = undefined;
        switch (case) {
            .@"kebab-case" => {
                for (snake_case, 0..) |byte, index| output[index] = if (byte == '_') '-' else byte;
                break :blk comptime_slice(output.len, &output, snake_case.len);
            },
            .UPPER_CASE => {
                const len = std.ascii.upperString(output[0..], snake_case).len;
                break :blk comptime_slice(output.len, &output, len);
            },
            .camelCase, .PascalCase => {
                var len: usize = 0;
                var iterator = std.mem.tokenizeScalar(u8, snake_case, '_');
                while (iterator.next()) |word| {
                    _ = std.ascii.lowerString(output[len..], word);
                    output[len] = std.ascii.toUpper(output[len]);
                    len += word.len;
                }

                output[0] = switch (case) {
                    .camelCase => std.ascii.toLower(output[0]),
                    .PascalCase => std.ascii.toUpper(output[0]),
                    .@"kebab-case", .UPPER_CASE => unreachable,
                };

                break :blk comptime_slice(output.len, &output, len);
            },
        }
    };
}

fn comptime_slice(comptime N: usize, comptime array: *[N]u8, comptime len: usize) []const u8 {
    return array[0..len];
}

/// Use a dynamic bitset for larger sizes.
pub fn BitSetType(comptime with_capacity: u9) type {
    assert(with_capacity <= 256);

    return struct {
        // While mathematically 0 and 1 are symmetric, we intentionally bias the API to use zeros
        // default, as zero-initialization reduces binary size.
        bits: Word = 0,

        pub const Word = for (.{ u8, u16, u32, u64, u128, u256 }) |w| {
            if (@bitSizeOf(w) >= with_capacity) break w;
        } else unreachable;

        const BitSet = @This();

        pub fn is_set(bit_set: BitSet, index: usize) bool {
            assert(index < bit_set.capacity());
            return bit_set.bits & bit(index) != 0;
        }

        pub fn count(bit_set: BitSet) usize {
            return @popCount(bit_set.bits);
        }

        pub inline fn capacity(_: BitSet) usize {
            return with_capacity;
        }

        pub fn full(bit_set: BitSet) bool {
            return bit_set.count() == bit_set.capacity();
        }

        pub fn empty(bit_set: BitSet) bool {
            return bit_set.bits == 0;
        }

        pub fn first_set(bit_set: BitSet) ?usize {
            if (bit_set.bits == 0) return null;
            return @ctz(bit_set.bits);
        }

        pub fn first_unset(bit_set: BitSet) ?usize {
            const result = @ctz(~bit_set.bits);
            return if (result < bit_set.capacity()) result else null;
        }

        pub fn set(bit_set: *BitSet, index: usize) void {
            assert(index < bit_set.capacity());
            bit_set.bits |= bit(index);
        }

        pub fn unset(bit_set: *BitSet, index: usize) void {
            assert(index < bit_set.capacity());
            bit_set.bits &= ~bit(index);
        }

        pub fn set_value(bit_set: *BitSet, index: usize, value: bool) void {
            if (value) {
                bit_set.set(index);
            } else {
                bit_set.unset(index);
            }
        }

        fn bit(index: usize) Word {
            assert(index < with_capacity);
            return @as(Word, 1) << @intCast(index);
        }

        pub fn iterate(bit_set: BitSet) Iterator {
            return .{ .bits_remain = bit_set.bits };
        }

        pub const Iterator = struct {
            bits_remain: Word,

            pub fn next(iterator: *Iterator) ?usize {
                if (iterator.bits_remain == 0) return null;
                const index = @ctz(iterator.bits_remain);
                iterator.bits_remain &= iterator.bits_remain - 1;
                return index;
            }
        };
    };
}

/// PRNG with a deterministic seed, used for tests.
/// Based on the WyRand algorithm.
pub const PRNG = struct {
    state: u64,

    pub const Ratio = struct {
        numerator: u64,
        denominator: u64,

        pub fn format(
            ratio_value: Ratio,
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = options;
            if (fmt.len == 0) {
                try writer.print("{d}/{d}", .{ ratio_value.numerator, ratio_value.denominator });
            } else {
                try writer.print("{{fmt}}", .{});
            }
        }
    };

    pub fn ratio(numerator: u64, denominator: u64) Ratio {
        assert(numerator <= denominator);
        return .{ .numerator = numerator, .denominator = denominator };
    }

    pub fn from_seed(seed: u64) PRNG {
        var prng: PRNG = .{ .state = seed };
        // Ensure the state is non-zero.
        _ = prng.next();
        return prng;
    }

    /// Determinstic seed so failures can be reproduced.
    pub fn from_seed_testing() PRNG {
        return from_seed(0x7a82_3a13_e83c_77a2);
    }

    fn next(prng: *PRNG) u64 {
        prng.state +%= 0xa076_1d64_78bd_642f;
        const t: u128 = @as(u128, prng.state) * @as(u128, prng.state);
        return @truncate(t >> 64);
    }

    pub fn fill(prng: *PRNG, target: []u8) void {
        var offset: usize = 0;
        while (offset < target.len) : (offset += 8) {
            const word = prng.next();
            const size = @min(8, target.len - offset);
            @memcpy(target[offset..][0..size], std.mem.asBytes(&word)[0..size]);
        }
    }

    pub fn int_inclusive(prng: *PRNG, Int: anytype, max: Int) Int {
        return prng.range_inclusive(Int, 0, max);
    }

    pub fn index(prng: *PRNG, slice: anytype) usize {
        const Int = std.meta.Child(@TypeOf(slice));
        return prng.range_inclusive(Int, 0, slice.len - 1);
    }

    pub fn range_inclusive(prng: *PRNG, Int: type, min: Int, max: Int) Int {
        const Unsigned = std.meta.Int(.unsigned, @bitSizeOf(Int));
        assert(min <= max);
        const range: Unsigned = @intCast(max - min);
        const result: Unsigned = @intCast(prng.int(Unsigned) % (range + 1));
        return min + @as(Int, @intCast(result));
    }

    pub fn int(prng: *PRNG, Int: type) Int {
        const Unsigned = std.meta.Int(.unsigned, @bitSizeOf(Int));
        const value = prng.next() & maxIntMask(Unsigned);
        if (@bitSizeOf(Int) < 64) {
            // Truncate.
            return @intCast(value);
        }
        return @bitCast(value);
    }

    fn maxIntMask(comptime Int: type) Int {
        // The subsequent @intCast truncates to the destination width anyway;
        // masking with maxInt keeps the low bits uniform without any shift
        // overflow at comptime for narrower types (e.g. u63).
        return std.math.maxInt(Int);
    }

    pub fn boolean(prng: *PRNG) bool {
        return prng.bit(u8) == 1;
    }

    pub fn bit(prng: *PRNG, comptime Word: type) Word {
        const bytes = std.mem.asBytes(&prng.next());
        return bytes[0] & (std.math.maxInt(Word));
    }

    pub fn chance(prng: *PRNG, probability: Ratio) bool {
        const threshold = probability.numerator;
        const denominator = probability.denominator;
        assert(threshold <= denominator);
        return prng.range_inclusive(u64, 0, denominator - 1) < threshold;
    }

    pub fn enum_uniform(prng: *PRNG, Enum: type) Enum {
        return prng.enum_index(Enum, 0, std.enums.values(Enum).len - 1);
    }

    fn enum_index(prng: *PRNG, Enum: type, min: usize, max: usize) Enum {
        assert(min <= max);
        const index_value = prng.range_inclusive(usize, min, max);
        return std.enums.values(Enum)[index_value];
    }
};

const testing = std.testing;

test "copy_left" {
    const a = try testing.allocator.alloc(usize, 8);
    defer testing.allocator.free(a);

    for (a, 0..) |*v, i| v.* = i;
    copy_left(.exact, usize, a[0..6], a[2..]);
    try testing.expect(std.mem.eql(usize, a, &.{ 2, 3, 4, 5, 6, 7, 6, 7 }));
}

test "copy_disjoint" {
    const a = try testing.allocator.alloc(u8, 8);
    defer testing.allocator.free(a);

    @memcpy(a, "abcdefgh");
    copy_disjoint(.inexact, u8, a[2..], "XY");
    try testing.expect(std.mem.eql(u8, a, "abXYefgh"));
}

test "BitSetType" {
    var bitset: BitSetType(16) = .{};
    try testing.expect(bitset.empty());

    bitset.set(3);
    try testing.expect(bitset.is_set(3));
    try testing.expect(!bitset.is_set(4));
    try testing.expectEqual(@as(usize, 1), bitset.count());

    bitset.set_value(9, true);
    bitset.set_value(3, false);
    try testing.expect(!bitset.is_set(3));
    try testing.expect(bitset.is_set(9));
    try testing.expectEqual(@as(usize, 1), bitset.count());
}

test "PRNG is deterministic" {
    var prng = PRNG.from_seed(1234);
    const a = prng.int(u64);
    var prng_again = PRNG.from_seed(1234);
    try testing.expectEqual(a, prng_again.int(u64));
}

test "to_case kebab" {
    // `to_case` yields a comptime-only slice; concatenating at comptime
    // materializes the result as static data (the production pattern).
    const kebab = comptime "x-" ++ to_case("message_ttl", .@"kebab-case");
    try testing.expectEqualStrings("x-message-ttl", kebab);
    const max_length = comptime "x-" ++ to_case("max_length", .@"kebab-case");
    try testing.expectEqualStrings("x-max-length", max_length);
}

test "unique_u128 is never zero" {
    try testing.expect(unique_u128() != 0);
}

test "zeroed" {
    const a: [8]u8 = .{ 0, 0, 0, 0, 0, 0, 0, 0 };
    const b: [8]u8 = .{ 0, 0, 1, 0, 0, 0, 0, 0 };
    try testing.expect(zeroed(&a));
    try testing.expect(!zeroed(&b));
}
