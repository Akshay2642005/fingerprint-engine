const std = @import("std");

const model = @import("model.zig");
const defs = @import("definitions.zig");

const FeatureDefinition = model.FeatureDefinition;
const FeatureID = model.FeatureID;

const feature_count = @typeInfo(FeatureID).@"enum".fields.len;
const real_feature_count = feature_count - 1; // Exclude Count sentinel
const lookup = buildLookupTable();

pub const Registry = struct {
    pub inline fn get(id: FeatureID) *const FeatureDefinition {
        return lookup[@intFromEnum(id)].?;
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
