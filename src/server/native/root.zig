const std = @import("std");
const core = @import("core");

pub export fn hello() void {
    _ = core.version;
    _ = core.native_project_name;

    std.debug.print("Hello from Fingerprint Engine!\n", .{});
}
