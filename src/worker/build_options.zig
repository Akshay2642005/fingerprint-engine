//! Standalone-analysis fallback for `@import("build_options")` from
//! src/worker/. See src/build_options.zig — same contract, same warning: this
//! stub is shadowed by the build-injected module and must never leak into a
//! build artifact.

pub const version = "0.0.0-dev";
