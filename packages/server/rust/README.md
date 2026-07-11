# fingerprint-sdk

[![crates.io version](https://img.shields.io/crates/v/fingerprint-sdk)](https://crates.io/crates/fingerprint-sdk)

Rust bindings for the Fingerprint Engine native library. Provides fingerprint collection, SHA-256 digest computation, and similarity matching via FFI.

## Requirements

- Rust 2021 edition
- The compiled native library (`libfingerprint.a`)

Build the native library:

```bash
zig build native
```

## Usage

```toml
[dependencies]
fingerprint-sdk = "0.1.0"
```

```rust
use fingerprint_sdk::{FingerprintEngine, FeatureID};

let mut engine = FingerprintEngine::new().unwrap();
engine.add_boolean(FeatureID::CookieEnabled, true).unwrap();
engine.add_string(FeatureID::UserAgent, "Mozilla/5.0 ...").unwrap();
let digest = engine.compute().unwrap();
println!("{:02x?}", digest);
```

## Development

```bash
# Build the native library
zig build native

# Run tests
cd packages/server/rust
cargo test

# Run CLI example
cargo run --example fingerprint_cli
```

## License

MIT
