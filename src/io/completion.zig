const std = @import("std");

/// A zero-allocation completion: `callback` is invoked with the embedded
/// `*Completion` once an async operation finishes. Consumers embed a
/// `Completion` in their own struct and recover the parent with
/// `@fieldParentPtr("completion", self)`. Callbacks run on the thread that
/// completes them (the executor's thread), never concurrently.
pub const Completion = struct {
    context: ?*anyopaque = null,
    callback: *const fn (*Completion) void,

    pub fn init(callback: *const fn (*Completion) void, context: ?*anyopaque) Completion {
        return .{ .context = context, .callback = callback };
    }

    /// Invokes the callback. Called exactly once per operation.
    pub fn complete(self: *Completion) void {
        self.callback(self);
    }
};
