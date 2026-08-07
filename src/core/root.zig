// Core algorithm modules. The runtime model lives in the `model` module
// (src/model/); core depends on it via relative imports only.
pub const normalization = @import("normalization/root.zig");
pub const hashing = @import("hashing/root.zig");
pub const validation = @import("validation/root.zig");
pub const similarity = @import("similarity/root.zig");
pub const entropy = @import("entropy/root.zig");
pub const risk = @import("risk/root.zig");
