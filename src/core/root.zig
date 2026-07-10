pub const features = @import("features/root.zig");
pub const fingerprint = @import("fingerprint/root.zig");
pub const serialization = @import("serialization/root.zig");
pub const normalization = @import("normalization/root.zig");

pub const native_project_name = "fingerprint-engine";
pub const wasm_project_name = "fingerprint-sdk";
pub const version = "0.1.0";
