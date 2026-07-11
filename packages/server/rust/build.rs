/// Build script for fingerprint-sdk Rust crate.
///
/// Instructs cargo to link against the Zig-compiled native static library.
/// The library is expected at ../../zig-out/lib/libfingerprint.a relative
/// to this crate.

use std::path::PathBuf;

fn main() {
    // Path to the built library
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let lib_dir = manifest_dir
        .parent()           // packages/server/rust/.. → packages/server/
        .and_then(|p| p.parent())   // packages/.. → packages/
        .and_then(|p| p.parent())   // ../../.. → root
        .map(|root| root.join("zig-out").join("lib"))
        .expect("Failed to resolve zig-out/lib path");

    // Tell cargo where to find the library
    println!("cargo:rustc-link-search={}", lib_dir.display());
    println!("cargo:rustc-link-lib=static=fingerprint");
    println!("cargo:rerun-if-changed=build.rs");

    // Rebuild if the library changes
    println!("cargo:rerun-if-changed={}/libfingerprint.a", lib_dir.display());
}
