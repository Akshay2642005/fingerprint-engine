const std = @import("std");
const Operation = @import("operation.zig").Operation;
const Status = @import("status.zig").Status;
const Request = @import("request.zig").Request;
const Response = @import("response.zig").Response;
const ops = @import("ops/root.zig");

/// Every op handler has the same shape: decode from the request, compute,
/// write into the response buffer. Intermediate allocations come from
/// `scratch` (the caller's arena).
const Handler = *const fn (
    req: *const Request,
    res: *Response,
    scratch: std.mem.Allocator,
) anyerror!void;

/// Comptime dispatch table — one row per operation. Adding an operation is a
/// new ops/*.zig file plus one row here; there is no runtime registration.
const dispatch_table = [_]struct { op: Operation, handler: Handler }{
    .{ .op = .validate, .handler = ops.validate.handle },
    .{ .op = .normalize, .handler = ops.normalize.handle },
    .{ .op = .serialize, .handler = ops.serialize.handle },
    .{ .op = .deserialize, .handler = ops.deserialize.handle },
    .{ .op = .hash, .handler = ops.hash.handle },
    .{ .op = .entropy, .handler = ops.entropy.handle },
    .{ .op = .similarity, .handler = ops.similarity.handle },
    .{ .op = .risk, .handler = ops.risk.handle },
    .{ .op = .package, .handler = ops.package.handle },
};

/// Looks up the handler for an operation. Unknown (or future) operations
/// return null so the caller can reply `invalid_request`.
pub fn lookup(op: Operation) ?Handler {
    inline for (dispatch_table) |row| {
        if (row.op == op) return row.handler;
    }
    return null;
}

/// Entry point: dispatch a request and fill the response. Never throws
/// across the boundary — every failure is folded into `res.status`.
pub fn process(req: *const Request, res: *Response, scratch: std.mem.Allocator) !void {
    res.operation = req.operation;
    res.status = .ok;
    res.payload_len = 0;

    if (req.codec != .binary and req.codec != .json) {
        res.status = .invalid_request;
        return;
    }

    const handler = lookup(req.operation) orelse {
        res.status = .invalid_request;
        return;
    };

    handler(req, res, scratch) catch |err| {
        res.payload_len = 0;
        res.status = mapError(err);
    };
}

fn mapError(err: anyerror) Status {
    return switch (err) {
        error.InvalidPayload, error.InvalidMagic, error.Truncated => .invalid_payload,
        error.UnsupportedVersion => .unsupported_version,
        error.InvalidInput => .invalid_input,
        error.OutOfMemory => .out_of_memory,
        error.NoSpaceLeft, error.BufferFull => .buffer_overflow,
        else => .internal_error,
    };
}

// ── Per-op convenience wrappers (D3) ──
// Each pins `operation` on a copy of the request and delegates to process().
// The public facade can grow op-by-op without touching the dispatch table.

pub fn validate(req: *const Request, res: *Response, scratch: std.mem.Allocator) !void {
    return withOperation(req, res, scratch, .validate);
}

pub fn normalize(req: *const Request, res: *Response, scratch: std.mem.Allocator) !void {
    return withOperation(req, res, scratch, .normalize);
}

pub fn serialize(req: *const Request, res: *Response, scratch: std.mem.Allocator) !void {
    return withOperation(req, res, scratch, .serialize);
}

pub fn deserialize(req: *const Request, res: *Response, scratch: std.mem.Allocator) !void {
    return withOperation(req, res, scratch, .deserialize);
}

pub fn hash(req: *const Request, res: *Response, scratch: std.mem.Allocator) !void {
    return withOperation(req, res, scratch, .hash);
}

pub fn entropy(req: *const Request, res: *Response, scratch: std.mem.Allocator) !void {
    return withOperation(req, res, scratch, .entropy);
}

pub fn similarity(req: *const Request, res: *Response, scratch: std.mem.Allocator) !void {
    return withOperation(req, res, scratch, .similarity);
}

pub fn risk(req: *const Request, res: *Response, scratch: std.mem.Allocator) !void {
    return withOperation(req, res, scratch, .risk);
}

pub fn package(req: *const Request, res: *Response, scratch: std.mem.Allocator) !void {
    return withOperation(req, res, scratch, .package);
}

fn withOperation(
    req: *const Request,
    res: *Response,
    scratch: std.mem.Allocator,
    op: Operation,
) !void {
    var r = req.*;
    r.operation = op;
    return process(&r, res, scratch);
}
