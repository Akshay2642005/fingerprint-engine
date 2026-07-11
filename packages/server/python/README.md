# fingerprint-sdk

[![PyPI version](https://img.shields.io/pypi/v/fingerprint-sdk)](https://pypi.org/project/fingerprint-sdk/)

Python bindings for the Fingerprint Engine native library. Provides fingerprint collection, SHA-256 digest computation, and similarity matching via ctypes.

## Requirements

- Python 3.9+
- The compiled native library (`libfingerprint.a` / `fingerprint.lib`)

Build the native library:

```bash
zig build native
```

## Installation

```bash
pip install fingerprint-sdk
```

## Quick Start

```python
from fingerprint_sdk import FingerprintEngine, FeatureID

engine = FingerprintEngine()
engine.add_boolean(FeatureID.COOKIE_ENABLED, True)
engine.add_string(FeatureID.USER_AGENT,
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) ...")
engine.add_integer(FeatureID.HARDWARE_CONCURRENCY, 8)

digest = engine.compute()
print(f"Digest: {digest.hex()}")
```

## API

### FingerprintEngine

| Method | Description |
| -------- | ------------- |
| `add_boolean(id, value)` | Add a boolean feature |
| `add_integer(id, value)` | Add an integer feature |
| `add_float(id, value)` | Add a float feature |
| `add_string(id, value)` | Add a string feature (UTF-8) |
| `add_bytes(id, value)` | Add a bytes feature |
| `add_string_array(id, value)` | Add a string array feature |
| `add_integer_array(id, value)` | Add an integer array feature |
| `add_float_array(id, value)` | Add a float array feature |
| `compute()` | Compute fingerprint digest (returns bytes) |
| `compute_hex()` | Compute fingerprint digest (returns hex string) |

## Development

```bash
# Build the native library
zig build native

# Test
cd packages/server/python
python examples/fingerprint_demo.py
```

## License

MIT
