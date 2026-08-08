const std = @import("std");
const builtin = @import("builtin");

// Fingerprint Engine Build System
//
// O(1) build: every top-level step is declared up front in a
// tuple and implemented by a small helper function. Everything — tests, wasm,
// benchmarks, the browser npm package, docs, automation scripts — builds
// through Zig.
//
// Module graph (dependencies flow downward, no cycles):
//   model           - runtime data model (src/model/), depends on nothing
//   core            - deterministic algorithms (src/core/), depends on model
//   serialization   - codecs (src/serialization/), depends on model
//   engine          - deterministic process dispatch (src/engine/), depends on model+core+serialization
//   io              - async transport primitives (src/io/), depends on nothing
//   adapter         - transport implementations (src/adapter/), depends on io
//   worker          - deterministic worker executable (src/worker/), depends on engine+adapter
//   browser         - WebAssembly target (src/browser/), depends on core+model
//   browser_package - build-time npm package generator (src/build/), depends on model
//   test_utils      - test helpers (tests/utils/), depends on model
//   bench_module    - benchmarks (src/bench/), depends on core+model+serialization
//
// Steps:
//   zig build test                  - run all unit tests (plus integration/e2e)
//   zig build test-integration      - run integration and e2e tests
//   zig build test-integration-build - build the integration test binary
//   zig build wasm                  - build the WebAssembly module
//   zig build worker                - build the worker executable
//   zig build bench                 - run performance benchmarks
//   zig build clients:browser       - build the browser npm package (dist/)
//   zig build docs                  - build docs (nested src/docs_website/)
//   zig build scripts -- <cmd>      - free-form automation scripts

const zig_version = std.SemanticVersion{
    .major = 0,
    .minor = 14,
    .patch = 1,
};

comptime {
    const zig_version_equal =
        zig_version.major == builtin.zig_version.major and
        zig_version.minor == builtin.zig_version.minor and
        zig_version.patch == builtin.zig_version.patch;
    if (!zig_version_equal) {
        @compileError(std.fmt.comptimePrint(
            "unsupported zig version: expected {}, found {}",
            .{ zig_version, builtin.zig_version },
        ));
    }
}

pub fn build(b: *std.Build) !void {
    // A compile error stack trace of 10 is arbitrary in size but helps with debugging.
    b.reference_trace = 10;

    // Top-level steps you can invoke on the command line.
    const build_steps = .{
        .@"test" = b.step("test", "Run all tests"),
        .test_integration = b.step("test-integration", "Run integration and e2e tests"),
        .test_integration_build = b.step("test-integration-build", "Build integration tests"),
        .wasm = b.step("wasm", "Build the browser WebAssembly module"),
        .worker = b.step("worker", "Build the fingerprint worker executable"),
        .bench = b.step("bench", "Run performance benchmarks"),
        .clients_browser = b.step("clients:browser", "Build the browser SDK npm package"),
        .docs = b.step("docs", "Build docs"),
        .scripts = b.step("scripts", "Free form automation scripts"),
        .scripts_build = b.step("scripts:build", "Build automation scripts"),
    };

    const mode = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSafe });
    const target = b.standardTargetOptions(.{});
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });

    // Model: runtime data model (feature definitions, registry, fingerprint
    // value types). Depends on nothing.
    const model = b.createModule(.{
        .root_source_file = b.path("src/model/root.zig"),
        .target = target,
        .optimize = mode,
    });

    // Core: deterministic algorithms (normalization, hashing, validation,
    // similarity, entropy, risk). Depends on Model.
    const core = b.createModule(.{
        .root_source_file = b.path("src/core/root.zig"),
        .target = target,
        .optimize = mode,
        .imports = &.{
            .{ .name = "model", .module = model },
        },
    });

    // Serialization: binary and JSON codecs for the model. Depends on Model.
    const serialization = b.createModule(.{
        .root_source_file = b.path("src/serialization/root.zig"),
        .target = target,
        .optimize = mode,
        .imports = &.{
            .{ .name = "model", .module = model },
        },
    });

    // Engine: deterministic request/response dispatch (operation, status,
    // request, response, process, per-op handlers). Depends on Core, Model,
    // and Serialization; imports no io/adapter/transport code.
    const engine = b.createModule(.{
        .root_source_file = b.path("src/engine/root.zig"),
        .target = target,
        .optimize = mode,
        .imports = &.{
            .{ .name = "model", .module = model },
            .{ .name = "core", .module = core },
            .{ .name = "serialization", .module = serialization },
        },
    });

    // IO: async transport primitives (message, ring buffer, channel,
    // completion, executor, frame, reader, writer, dispatcher). Depends on
    // nothing.
    const io = b.createModule(.{
        .root_source_file = b.path("src/io/root.zig"),
        .target = target,
        .optimize = mode,
    });

    // Adapter: transport implementations (loopback, tcp, framing helpers).
    // Depends on IO only — never on engine or serialization, so the engine
    // stays transport-agnostic.
    const adapter = b.createModule(.{
        .root_source_file = b.path("src/adapter/root.zig"),
        .target = target,
        .optimize = mode,
        .imports = &.{
            .{ .name = "io", .module = io },
        },
    });

    // Worker: the deterministic worker executable (D9, D16). Depends on
    // Engine and Adapter; contains no business logic.
    const worker = b.createModule(.{
        .root_source_file = b.path("src/worker/main.zig"),
        .target = target,
        .optimize = mode,
        .imports = &.{
            .{ .name = "engine", .module = engine },
            .{ .name = "adapter", .module = adapter },
            .{ .name = "io", .module = io },
        },
    });

    // Browser: WebAssembly SDK for collection and packaging. Depends on
    // Core and Model.
    //
    // The optimize mode is pinned to ReleaseSmall: the module is only ever
    // shipped as an inlined base64 payload inside the npm package, where
    // binary size dominates (ReleaseSafe wasm is ~8x larger). Tests run the
    // same logic natively, so debugging doesn't depend on the wasm mode.
    const browser = b.createModule(.{
        .root_source_file = b.path("src/browser/wasm/root.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSmall,
        .imports = &.{
            .{ .name = "core", .module = core },
            .{ .name = "model", .module = model },
        },
    });

    // Browser package generator: emits the npm package dist/ from the wasm
    // binary and the model definitions. Depends on Model.
    const browser_package = b.createModule(.{
        .root_source_file = b.path("src/build/browser_package.zig"),
        .target = target,
        .optimize = mode,
        .imports = &.{
            .{ .name = "model", .module = model },
        },
    });

    // Test utilities: assertions, generators, and mocks.
    const test_utils = b.createModule(.{
        .root_source_file = b.path("tests/utils/root.zig"),
        .target = target,
        .optimize = mode,
        .imports = &.{
            .{ .name = "model", .module = model },
        },
    });

    // Single test binary. tests/root.zig auto-discovers
    // and imports every test file under tests/.
    const test_core_module = b.createModule(.{
        .root_source_file = b.path("tests/root.zig"),
        .target = target,
        .optimize = mode,
        .imports = &.{
            .{ .name = "model", .module = model },
            .{ .name = "core", .module = core },
            .{ .name = "serialization", .module = serialization },
            .{ .name = "engine", .module = engine },
            .{ .name = "io", .module = io },
            .{ .name = "adapter", .module = adapter },
            .{ .name = "worker", .module = worker },
            .{ .name = "test_utils", .module = test_utils },
            .{ .name = "browser_package", .module = browser_package },
        },
    });

    // Benchmark executable with core, model, and serialization as deps.
    const bench_module = b.createModule(.{
        .root_source_file = b.path("src/bench/main.zig"),
        .target = target,
        .optimize = mode,
        .imports = &.{
            .{ .name = "core", .module = core },
            .{ .name = "model", .module = model },
            .{ .name = "serialization", .module = serialization },
        },
    });

    // zig build test
    build_test(b, build_steps.@"test", .{ .test_core_module = test_core_module });

    // zig build wasm
    const wasm = build_wasm(b, .{
        .wasm_step = build_steps.wasm,
        .install_step = b.getInstallStep(),
    }, .{ .browser_module = browser });

    // zig build worker
    const worker_exe = build_worker(b, .{
        .worker_step = build_steps.worker,
        .install_step = b.getInstallStep(),
    }, .{ .worker_module = worker });

    // zig build bench
    const bench = build_bench(b, build_steps.bench, .{ .bench_module = bench_module });

    // zig build clients:browser
    build_browser_client(b, build_steps.clients_browser, .{
        .wasm = wasm,
        .browser_package_module = browser_package,
    });

    // zig build scripts, zig build scripts:build
    const scripts_exe = build_scripts(b, .{
        .scripts = build_steps.scripts,
        .scripts_build = build_steps.scripts_build,
    }, .{
        .target = target,
        .model = model,
        .serialization = serialization,
        .engine = engine,
    });

    // zig build test-integration, zig build test-integration-build
    build_test_integration(b, .{
        .test_integration = build_steps.test_integration,
        .test_integration_build = build_steps.test_integration_build,
    }, .{
        .target = target,
        .mode = mode,
        .bench_exe = bench.getEmittedBin(),
        .scripts_exe = scripts_exe.getEmittedBin(),
        .worker_exe = worker_exe.getEmittedBin(),
    });
    if (b.args == null) {
        // `zig build test -- <filter>` runs only matching unit tests; the
        // integration suite is reserved for the unfiltered run.
        build_steps.@"test".dependOn(build_steps.test_integration);
    }

    // zig build docs
    build_docs(b, build_steps.docs);
}

fn build_test(b: *std.Build, step: *std.Build.Step, options: struct {
    test_core_module: *std.Build.Module,
}) void {
    // Single test binary rooted at tests/root.zig, which
    // discovers and imports every test file under tests/ and verifies its own
    // import list (SNAP_UPDATE=1 regenerates it). `zig build test -- <filter>`
    // runs only the tests matching the filter.
    const tests = b.addTest(.{
        .name = "test-unit",
        .root_module = options.test_core_module,
        .filters = b.args orelse &.{},
    });
    const run = b.addRunArtifact(tests);
    // The registry walks tests/ relative to the repository root.
    run.setCwd(b.path("."));
    if (b.args != null) {
        // Don't cache test results if running a specific test.
        run.has_side_effects = true;
    }
    step.dependOn(&run.step);
}

fn build_wasm(b: *std.Build, steps: struct {
    wasm_step: *std.Build.Step,
    install_step: *std.Build.Step,
}, options: struct {
    browser_module: *std.Build.Module,
}) *std.Build.Step.Compile {
    // This executable has no entry point because it is loaded as a library
    // by JavaScript rather than executed as a standalone program.
    const wasm = b.addExecutable(.{
        .name = "fingerprint",
        .root_module = options.browser_module,
    });
    wasm.entry = .disabled;
    wasm.rdynamic = true;

    // addInstallArtifact (returns *Step.InstallArtifact) instead of
    // installArtifact (returns void) so custom steps can depend on the
    // install step rather than just the compile step. Without this,
    // `zig build wasm` compiles the binary but never copies it to zig-out/.
    const wasm_install = b.addInstallArtifact(wasm, .{});
    steps.install_step.dependOn(&wasm_install.step);
    steps.wasm_step.dependOn(&wasm_install.step);
    return wasm;
}

fn build_worker(b: *std.Build, steps: struct {
    worker_step: *std.Build.Step,
    install_step: *std.Build.Step,
}, options: struct {
    worker_module: *std.Build.Module,
}) *std.Build.Step.Compile {
    const worker = b.addExecutable(.{
        .name = "worker",
        .root_module = options.worker_module,
    });
    const worker_install = b.addInstallArtifact(worker, .{});
    steps.install_step.dependOn(&worker_install.step);
    steps.worker_step.dependOn(&worker_install.step);
    return worker;
}

fn build_bench(b: *std.Build, step: *std.Build.Step, options: struct {
    bench_module: *std.Build.Module,
}) *std.Build.Step.Compile {
    const bench = b.addExecutable(.{
        .name = "fingerprint-bench",
        .root_module = options.bench_module,
    });
    const run = b.addRunArtifact(bench);
    step.dependOn(&run.step);
    return bench;
}

fn build_browser_client(b: *std.Build, step: *std.Build.Step, options: struct {
    wasm: *std.Build.Step.Compile,
    browser_package_module: *std.Build.Module,
}) void {
    const generator = b.addExecutable(.{
        .name = "browser_package",
        .root_module = options.browser_package_module,
    });
    const run = b.addRunArtifact(generator);
    // Inputs: wasm binary, UMD template, package metadata, demo page, and the
    // package directory the generator writes dist/ into.
    run.addFileArg(options.wasm.getEmittedBin());
    run.addFileArg(b.path("src/clients/browser/scripts/fingerprint-umd-template.js"));
    run.addFileArg(b.path("src/clients/browser/package.json"));
    run.addFileArg(b.path("src/browser/bindings/demo.html"));
    run.addDirectoryArg(b.path("src/clients/browser"));
    step.dependOn(&run.step);
}

fn build_scripts(b: *std.Build, steps: struct {
    scripts: *std.Build.Step,
    scripts_build: *std.Build.Step,
}, options: struct {
    target: std.Build.ResolvedTarget,
    model: *std.Build.Module,
    serialization: *std.Build.Module,
    engine: *std.Build.Module,
}) *std.Build.Step.Compile {
    const scripts_exe = b.addExecutable(.{
        .name = "scripts",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/scripts.zig"),
            .target = options.target,
            .optimize = .Debug,
            .imports = &.{
                .{ .name = "model", .module = options.model },
                .{ .name = "serialization", .module = options.serialization },
                .{ .name = "engine", .module = options.engine },
            },
        }),
    });
    steps.scripts_build.dependOn(
        &b.addInstallArtifact(scripts_exe, .{}).step,
    );

    const scripts_run = b.addRunArtifact(scripts_exe);
    scripts_run.setEnvironmentVariable("ZIG_EXE", b.graph.zig_exe);
    // Fixture paths in scripts are repository-root-relative.
    scripts_run.setCwd(b.path("."));
    if (b.args) |args| scripts_run.addArgs(args);
    steps.scripts.dependOn(&scripts_run.step);
    return scripts_exe;
}

fn build_test_integration(b: *std.Build, steps: struct {
    test_integration: *std.Build.Step,
    test_integration_build: *std.Build.Step,
}, options: struct {
    target: std.Build.ResolvedTarget,
    mode: std.builtin.OptimizeMode,
    bench_exe: std.Build.LazyPath,
    scripts_exe: std.Build.LazyPath,
    worker_exe: std.Build.LazyPath,
}) void {
    // Integration tests: the test binary contains no engine
    // code and only interacts with the engine through pre-built executables,
    // whose paths are injected as build options. addOptionPath tracks the
    // executables as dependencies, so they are built before the test binary.
    const integration_tests_options = b.addOptions();
    integration_tests_options.addOptionPath("bench_exe", options.bench_exe);
    integration_tests_options.addOptionPath("scripts_exe", options.scripts_exe);
    integration_tests_options.addOptionPath("worker_exe", options.worker_exe);
    const integration_tests = b.addTest(.{
        .name = "test-integration",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/integration_tests.zig"),
            .target = options.target,
            .optimize = options.mode,
        }),
        .filters = b.args orelse &.{},
    });
    integration_tests.root_module.addOptions("test_options", integration_tests_options);
    steps.test_integration_build.dependOn(&b.addInstallArtifact(integration_tests, .{}).step);

    const run_integration_tests = b.addRunArtifact(integration_tests);
    // Fixture files (tests/fixtures/) are read relative to the repository
    // root, matching the unit test runner's cwd.
    run_integration_tests.setCwd(b.path("."));
    if (b.args != null) {
        // Don't cache test results if running a specific test.
        run_integration_tests.has_side_effects = true;
    }
    steps.test_integration.dependOn(&run_integration_tests.step);
}

fn build_docs(b: *std.Build, step: *std.Build.Step) void {
    const nested_build = b.addSystemCommand(&.{ b.graph.zig_exe, "build" });
    nested_build.setCwd(b.path("./src/docs_website/"));
    step.dependOn(&nested_build.step);
}
