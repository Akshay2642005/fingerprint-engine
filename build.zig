const std = @import("std");

// Fingerprint Engine Build System
//
// Build Targets:
//   zig build           - Build all installable artifacts (WASM)
//   zig build wasm      - Build the browser WebAssembly SDK
//   zig build test      - Execute all unit tests and fuzz tests
//   zig build bench     - Run performance benchmarks
//
// Module Architecture (dependencies flow downward, no cycles):
//   Model        - Runtime data model (src/model/)
//   Core         - Deterministic algorithms, depends on Model (src/core/)
//   Serialization- Codecs for the model, depends on Model (src/serialization/)
//   Browser      - WebAssembly target for collection/packaging (src/browser/)
//
// The engine is a deterministic computation engine: Model defines the data,
// Core runs the algorithms, Serialization moves bytes in and out. Transport,
// adapters, and workers live outside src/ and are added in later commits.
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

    // Model Module
    // The runtime data model: feature definitions, registry, and the
    // fingerprint value types. Depends on nothing.
    const model = b.createModule(.{
        .root_source_file = b.path("src/model/root.zig"),
        .target = native_target,
        .optimize = optimize,
    });

    // Core Module
    // Deterministic algorithms (normalization, hashing, validation,
    // similarity, entropy, risk). Depends on Model.
    const core = b.createModule(.{
        .root_source_file = b.path("src/core/root.zig"),
        .target = native_target,
        .optimize = optimize,
        .imports = &.{
            .{
                .name = "model",
                .module = model,
            },
        },
    });

    // Serialization Module
    // Binary and JSON codecs for the model. Depends on Model.
    const serialization = b.createModule(.{
        .root_source_file = b.path("src/serialization/root.zig"),
        .target = native_target,
        .optimize = optimize,
        .imports = &.{
            .{
                .name = "model",
                .module = model,
            },
        },
    });

    // Browser Module
    // Produces the WebAssembly SDK consumed by browsers for collection,
    // validation, and packaging. Imports Core and Model.
    const browser = b.createModule(.{
        .root_source_file = b.path("src/browser/wasm/root.zig"),
        .target = wasm_target,
        .optimize = optimize,
        .imports = &.{
            .{
                .name = "core",
                .module = core,
            },
            .{
                .name = "model",
                .module = model,
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

    // Install Artifacts
    // Create install steps and register them with both the default "install"
    // step (runs on `zig build`) and the custom "wasm" step.
    //
    // NOTE: We use addInstallArtifact (returns *Step.InstallArtifact) instead
    // of installArtifact (returns void) so custom steps can depend on the
    // install step rather than just the compile step. Without this,
    // `zig build wasm` compiles the binary but never copies it to zig-out/.
    const wasm_install = b.addInstallArtifact(wasm, .{});
    b.getInstallStep().dependOn(&wasm_install.step);

    // Unit Tests
    // Tests live in tests/ outside src/ — no embedded tests in production code.
    // The single test binary imports every test module for fast iteration.

    // Test utilities module — provides assertions, generators, and mocks.
    const test_utils = b.createModule(.{
        .root_source_file = b.path("tests/utils/root.zig"),
        .target = native_target,
        .optimize = optimize,
        .imports = &.{
            .{
                .name = "model",
                .module = model,
            },
        },
    });

    const test_core_module = b.createModule(.{
        .root_source_file = b.path("tests/root.zig"),
        .target = native_target,
        .optimize = optimize,
        .imports = &.{
            .{
                .name = "model",
                .module = model,
            },
            .{
                .name = "core",
                .module = core,
            },
            .{
                .name = "serialization",
                .module = serialization,
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
    // These depend on the install steps (not compile steps) so the artifacts
    // are actually copied to zig-out/.
    const wasm_step = b.step(
        "wasm",
        "Build the browser WebAssembly SDK",
    );
    wasm_step.dependOn(&wasm_install.step);

    const test_step = b.step(
        "test",
        "Execute all tests",
    );
    test_step.dependOn(&run_tests_core.step);

    // Benchmark executable
    // Build as a standalone executable with core, model, and serialization
    // as deps via the root module.
    const bench_module = b.createModule(.{
        .root_source_file = b.path("tools/bench/main.zig"),
        .target = native_target,
        .optimize = optimize,
        .imports = &.{
            .{
                .name = "core",
                .module = core,
            },
            .{
                .name = "model",
                .module = model,
            },
            .{
                .name = "serialization",
                .module = serialization,
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
