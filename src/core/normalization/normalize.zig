const std = @import("std");
const fingerprint = @import("../fingerprint/root.zig");
const TypeWarning = @import("types.zig").TypeWarning;
const BoundWarning = @import("bounds.zig").BoundWarning;
const validateTypes = @import("types.zig").validateTypes;
const checkAllBounds = @import("bounds.zig").checkAllBounds;

const Fingerprint = fingerprint.Fingerprint;

/// Combined normalization warning — either a type mismatch or a bound violation.
pub const NormalizationWarning = union(enum) {
    type_mismatch: TypeWarning,
    bound_violation: BoundWarning,
};

/// Runs all normalization passes on a fingerprint:
/// - Type validation (every feature's value type matches its definition)
/// - Bounds validation (integer ranges, string lengths, etc.)
///
/// Returns a flat slice of all warnings detected. Empty = clean fingerprint.
/// Caller owns the returned memory (free with `allocator.free(warnings)`).
pub fn normalize(fp: Fingerprint, allocator: std.mem.Allocator) ![]NormalizationWarning {
    var warnings: std.ArrayList(NormalizationWarning) = .empty;
    defer warnings.deinit(allocator);

    // Type validation
    const type_warnings = try validateTypes(fp, allocator);
    defer allocator.free(type_warnings);
    for (type_warnings) |tw| {
        try warnings.append(allocator, NormalizationWarning{ .type_mismatch = tw });
    }

    // Bounds validation
    const bound_warnings = try checkAllBounds(fp, allocator);
    defer allocator.free(bound_warnings);
    for (bound_warnings) |bw| {
        try warnings.append(allocator, NormalizationWarning{ .bound_violation = bw });
    }

    return try warnings.toOwnedSlice(allocator);
}
