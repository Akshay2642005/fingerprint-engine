const core = @import("core");

pub export fn add(a: i32, b: i32) i32 {
    _ = core.version;
    _ = core.wasm_project_name;
    return a + b;
}
