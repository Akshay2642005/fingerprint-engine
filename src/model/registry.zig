const std = @import("std");

const model = @import("feature.zig");
const defs = @import("definitions.zig");

const FeatureDefinition = model.FeatureDefinition;
const FeatureID = model.FeatureID;

const feature_count = @typeInfo(FeatureID).@"enum".fields.len;
const real_feature_count = feature_count - 1; // Exclude Count sentinel
const lookup_table = buildLookupTable();

pub const Registry = struct {
    pub inline fn get(id: FeatureID) *const FeatureDefinition {
        const def = lookup_table[@intFromEnum(id)].?;
        std.debug.assert(def.name.len > 0);
        return def;
    }
    /// Tolerant lookup by raw wire id (m6-tolerant-lookup): returns the
    /// definition for a registered id, or null when the id is not a feature
    /// (out of range, or the Count sentinel). Never errors — decode uses this
    /// to skip unknown ids instead of rejecting the package (DESIGN §9.4.7).
    // story: m6-tolerant-lookup
    pub inline fn lookup(raw_id: u16) ?*const FeatureDefinition {
        if (raw_id >= feature_count) return null;
        return lookup_table[raw_id];
    }
    pub inline fn all() []const FeatureDefinition {
        return &defs.definitions;
    }
    pub inline fn count() usize {
        return defs.definitions.len;
    }
};

fn buildLookupTable() [feature_count]?*const FeatureDefinition {
    var table: [feature_count]?*const FeatureDefinition =
        [_]?*const FeatureDefinition{null} ** feature_count;

    for (&defs.definitions) |*definition| {
        const index = @intFromEnum(definition.id);
        if (index >= feature_count) {
            @compileError(std.fmt.comptimePrint("FeatureID '{s}' is out of bounds.", .{@tagName(definition.id)}));
        }
        if (table[index] != null) {
            @compileError(std.fmt.comptimePrint("Duplicate FeatureDefinition for '{s}'.", .{@tagName(definition.id)}));
        }
        table[index] = definition;
    }
    // Validate every FeatureID except Count (sentinel) has a definition.
    inline for (0..real_feature_count) |index| {
        if (table[index] == null) {
            const field = @typeInfo(FeatureID).@"enum".fields[index];
            @compileError(std.fmt.comptimePrint(
                "Missing FeatureDefinition for '{s}'.",
                .{field.name},
            ));
        }
    }

    return table;
}
