//! Standalone-analysis fallback for `@import("build_options")`.
//!
//! `zig build` injects the real `build_options` module (version derived from
//! `package_version` in build.zig, BUG-002) into every module that advertises
//! a version, and the injected module shadows this file. This stub exists only
//! so zls / `zig test file.zig` standalone analysis can resolve the import;
//! it must never reach a build artifact. If this value ever leaks into a
//! build, the BUG-002 regression tests (worker version, AMQP connection
//! properties) fail loudly.

pub const version = "0.0.0-dev";
