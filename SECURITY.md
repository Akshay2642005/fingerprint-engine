# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 0.1.x   | ✅ Active support  |

## Reporting a Vulnerability

If you discover a security vulnerability in the Fingerprint Engine, please report it responsibly:

1. **Do NOT open a public GitHub issue** for security vulnerabilities
2. Email security reports to: [SECURITY_EMAIL_PLACEHOLDER]
3. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact assessment
   - Suggested fix (if any)

We will respond within 48 hours and work with you to understand and address the issue.

## Security Considerations

### Input Validation

The Fingerprint Engine processes potentially untrusted input in several places:

- **Binary decode** (`decode`): Parses binary-encoded fingerprints from external sources
- **JSON decode** (`jsonDecode`): Parses JSON-encoded fingerprints
- **Feature values**: Accepts arbitrary strings, bytes, and arrays from browsers

All input paths are protected by:

1. **Bounds checking**: All array accesses are bounds-checked
2. **Type validation**: Feature values are validated against FeatureDefinition
3. **Bounds validation**: Integer and float values are checked against known ranges
4. **Length limits**: String and array lengths are bounded
5. **Fuzz testing**: Critical paths are fuzzed with `std.testing.fuzz`

### Memory Safety

- No heap allocation in value construction or hashing paths
- All allocations use Zig's safe allocator interface
- Memory is always freed on error paths (defer/errdefer patterns)
- No undefined behavior in normal operation

### Cryptographic Properties

- SHA-256 hashing uses Zig's constant-time implementation
- Feature ordering is deterministic (sorted by FeatureID)
- Type tags prevent cross-type collisions

### WASM Security

- The WASM module has no access to the filesystem or network
- All memory is linear and bounds-checked
- No JavaScript injection vectors (all data crosses the WASM boundary as bytes)

### Supply Chain

- No external dependencies beyond Zig 0.16.0 standard library
- CI runs on pinned GitHub Actions runners
- Releases are tagged and signed

## Security Testing

- Unit tests cover all error paths
- Fuzz tests exercise binary decode, normalization, and hashing with random inputs
- Static analysis via Zig's compile-time safety checks

## Updates

Security fixes will be released as patch versions (0.1.x) and clearly documented in the changelog.
