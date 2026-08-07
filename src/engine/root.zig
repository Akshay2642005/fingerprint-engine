//! Deterministic computation engine (D3). The engine knows nothing about
//! transports: it receives a `Request` (operation + codec + borrowed bytes),
//! computes, and writes into a caller-owned `Response` buffer. It never
//! clocks, never reads the network, and never allocates beyond `scratch`.
//!
//! Depends on: model, core, serialization. Imports no io/adapter code.

pub const Operation = @import("operation.zig").Operation;
pub const Status = @import("status.zig").Status;
pub const CodecID = @import("request.zig").CodecID;
pub const Request = @import("request.zig").Request;
pub const Response = @import("response.zig").Response;
pub const format = @import("format.zig");

pub const process = @import("engine.zig").process;
pub const lookup = @import("engine.zig").lookup;
pub const validate = @import("engine.zig").validate;
pub const normalize = @import("engine.zig").normalize;
pub const serialize = @import("engine.zig").serialize;
pub const deserialize = @import("engine.zig").deserialize;
pub const hash = @import("engine.zig").hash;
pub const entropy = @import("engine.zig").entropy;
pub const similarity = @import("engine.zig").similarity;
pub const risk = @import("engine.zig").risk;
pub const package = @import("engine.zig").package;
pub const ops = @import("ops/root.zig");
