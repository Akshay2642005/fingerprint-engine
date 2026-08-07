const std = @import("std");
const Completion = @import("completion.zig").Completion;
const RingBufferType = @import("ring_buffer.zig").RingBufferType;

/// Maximum completions a v1 executor can hold in flight.
pub const completion_capacity = 64;

/// A single-threaded FIFO executor. Completions are submitted in order and
/// drained in order — deterministic by construction, which makes executor
/// behavior reproducible in tests. Async lives at the transport boundary;
/// the engine itself never touches the executor.
pub const Executor = struct {
    queue: RingBufferType(*Completion, completion_capacity) = .init(),

    pub fn init() Executor {
        return .{};
    }

    pub fn hasPending(self: *const Executor) bool {
        return !self.queue.empty();
    }

    pub fn len(self: *const Executor) usize {
        return self.queue.len();
    }

    /// Enqueues a completion for the next drain; `error.QueueFull` when the
    /// in-flight budget is exhausted.
    pub fn submit(self: *Executor, completion: *Completion) error{QueueFull}!void {
        self.queue.push(completion) catch return error.QueueFull;
    }

    /// Processes exactly one pending completion; null when drained.
    pub fn tick(self: *Executor) ?*Completion {
        const completion = self.queue.pop() orelse return null;
        completion.complete();
        return completion;
    }

    /// Drains every pending completion; returns how many ran.
    pub fn run(self: *Executor) usize {
        var processed: usize = 0;
        while (self.tick()) |_| {
            processed += 1;
        }
        return processed;
    }
};
