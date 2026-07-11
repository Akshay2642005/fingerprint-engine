const std = @import("std");

// Fingerprint Engine Build System
// This build script defines the compilation pipeline for the Fingerprint
// Engine. The project is organized around three logical modules:
//   • Core     - Platform-independent fingerprint engine.
//   • Browser  - WebAssembly target for browser integration.
//   • Server   - Native static library for backend integrations (CGO, C, etc.).
// The Core module contains all fingerprinting algorithms and business logic.
// Browser and Server are thin platform-specific layers that import and expose
// the Core functionality.
// Current Build Targets
// zig build
//     Builds every installable artifact.
// zig build wasm
//     Builds the WebAssembly browser SDK.
// zig build native
//     Builds the native static library.
// zig build test
//     Executes the Core unit test suite.
// Future build targets may include:
//     zig build benchmark
//     zig build examples
//     zig build fuzz
//     zig build release
// The build graph is intentionally structured as a Directed Acyclic Graph
// (DAG), allowing Zig to schedule independent compilation tasks in parallel.
pub fn build(b: *std.Build) void {
    // These settings are shared across every build artifact unless explicitly
    // overridden.
    // Optimization mode selected by the user.
    // Examples:
    //     zig build -Doptimize=Debug
    //     zig build -Doptimize=ReleaseSafe
    //     zig build -Doptimize=ReleaseFast
    //     zig build -Doptimize=ReleaseSmall
    const optimize = b.standardOptimizeOption(.{});

    // Native compilation target.
    // This target is used for:
    //     • Native library
    //     • Unit tests
    //     • Future benchmarks
    const native_target = b.standardTargetOptions(.{});

    // Browser WebAssembly compilation target.
    // The browser SDK is compiled as a standalone WebAssembly module using
    // the freestanding environment.
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });

    // Core Module
    // The Core module contains the platform-independent fingerprint engine.
    // Every platform-specific SDK imports this module.
    const core = b.createModule(.{
        .root_source_file = b.path("src/core/root.zig"),
        .target = native_target,
        .optimize = optimize,
    });

    // Browser Module
    // Produces the WebAssembly SDK consumed by browsers.
    // This module imports the Core engine and exposes WebAssembly exports.
    const browser = b.createModule(.{
        .root_source_file = b.path("src/browser/wasm/root.zig"),
        .target = wasm_target,
        .optimize = optimize,
        .imports = &.{
            .{
                .name = "core",
                .module = core,
            },
        },
    });

    // Server Module
    // Produces the native library used by backend applications.
    // This module imports the Core engine and exposes native C-compatible
    // APIs for integration with Go, C, C++, Rust, or other languages.
    const server = b.createModule(.{
        .root_source_file = b.path("src/server/native/root.zig"),
        .target = native_target,
        .optimize = optimize,
        .imports = &.{
            .{
                .name = "core",
                .module = core,
            },
        },
    });

    // Browser WebAssembly Artifact
    // This executable has no entry point because it is loaded as a library
    // by JavaScript rather than executed as a standalone program.
    const wasm = b.addExecutable(.{
        .name = "fingerprint",
        .root_module = browser,
    });

    wasm.entry = .disabled;
    wasm.rdynamic = true;

    // Native Static Library
    // This library will later be linked by CGO and other native consumers.
    const native = b.addLibrary(.{
        .name = "fingerprint",
        .linkage = .static,
        .root_module = server,
    });

    // Install Artifacts
    // Installs build outputs into the Zig installation directory
    // (typically zig-out/).
    b.installArtifact(wasm);
    b.installArtifact(native);

    // Unit Tests
    // Tests live in tests/ outside src/ — no embedded tests in production code.
    // Each module gets its own test binary for fast iteration.

    // Test utilities module — provides assertions, generators, and mocks.
    const test_utils = b.createModule(.{
        .root_source_file = b.path("tests/utils/root.zig"),
        .target = native_target,
        .optimize = optimize,
        .imports = &.{
            .{
                .name = "core",
                .module = core,
            },
        },
    });

    const test_core_module = b.createModule(.{
        .root_source_file = b.path("tests/root.zig"),
        .target = native_target,
        .optimize = optimize,
        .imports = &.{
            .{
                .name = "core",
                .module = core,
            },
            .{
                .name = "server",
                .module = server,
            },
            .{
                .name = "test_utils",
                .module = test_utils,
            },
        },
    });

    const tests_core = b.addTest(.{
        .root_module = test_core_module,
    });

    // Run tests via IPC protocol so the build runner can format results.
    // Use `zig build test --summary all` for the full build summary with
    // pass/fail counts, timing, and cache info. Use `zt` (zt.bat) as a
    // shortcut for `zig build test --summary all`.
    const run_tests_core = b.addRunArtifact(tests_core);

    // Custom Build Steps
    // These commands provide convenient entry points for developers:
    const wasm_step = b.step(
        "wasm",
        "Build the browser WebAssembly SDK",
    );
    wasm_step.dependOn(&wasm.step);

    const native_step = b.step(
        "native",
        "Build the native static library",
    );
    native_step.dependOn(&native.step);

    const test_step = b.step(
        "test",
        "Execute all tests",
    );
    test_step.dependOn(&run_tests_core.step);

    const test_features_step = b.step(
        "test-features",
        "Execute features module tests only",
    );
    test_features_step.dependOn(&run_tests_core.step);

    // Benchmark executable
    // Build as a standalone executable with core as a dep via root module.
    const bench_module = b.createModule(.{
        .root_source_file = b.path("benchmark/main.zig"),
        .target = native_target,
        .optimize = optimize,
        .imports = &.{
            .{
                .name = "core",
                .module = core,
            },
        },
    });

    const bench_exe = b.addExecutable(.{
        .name = "fingerprint-bench",
        .root_module = bench_module,
    });

    const run_bench = b.addRunArtifact(bench_exe);

    const bench_step = b.step(
        "bench",
        "Run performance benchmarks",
    );
    bench_step.dependOn(&run_bench.step);
}
