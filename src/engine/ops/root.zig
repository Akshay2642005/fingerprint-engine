/// Per-operation handlers. Each op is a small, independent file: adding a
/// new operation is a new file plus one row in engine.zig's dispatch table.
pub const validate = @import("validate.zig");
pub const normalize = @import("normalize.zig");
pub const serialize = @import("serialize.zig");
pub const deserialize = @import("deserialize.zig");
pub const hash = @import("hash.zig");
pub const entropy = @import("entropy.zig");
pub const similarity = @import("similarity.zig");
pub const risk = @import("risk.zig");
pub const package = @import("package.zig");
