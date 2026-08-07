const std = @import("std");

// Fingerprint Engine docs build.
//
// Nested project wired from the root build via `zig build docs`.
// Snapshots the markdown sources in docs/
// (repo root) into zig-out/docs/, giving a clean publishable copy. Grows
// here as the docs deliverables land (TOC, cross-reference validation, ...).
pub fn build(b: *std.Build) !void {
    const install = b.addInstallDirectory(.{
        .source_dir = b.path("../../docs"),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    b.getInstallStep().dependOn(&install.step);
}
