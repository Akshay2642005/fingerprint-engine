const std = @import("std");

pub fn Entry(comptime Op: type, comptime Handler: type) type {
    return struct {
        op: Op,
        handler: Handler,
    };
}

/// A comptime operation → handler table. `Op` is any enum; `Handler` any
/// function pointer type. Dispatch is a compile-time linear scan over the
/// table (compiles to a switch), so there is no runtime registration and no
/// dynamic dispatch. The engine and the worker's message routing both build
/// a table from this.
pub fn DispatcherType(
    comptime Op: type,
    comptime Handler: type,
    comptime table: []const Entry(Op, Handler),
) type {
    return struct {
        /// Returns the handler for `op`, or null when the table has no row.
        pub fn lookup(op: Op) ?Handler {
            inline for (table) |entry| {
                if (entry.op == op) return entry.handler;
            }
            return null;
        }
    };
}
