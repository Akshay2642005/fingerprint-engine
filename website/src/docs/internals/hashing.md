---
title: "Hashing"
description: "The deterministic SHA-256 algorithm: sorted FeatureIDs, type-tagged values, and incremental Hasher.add/final producing a canonical digest."
category: "internals"
order: 2
crumbs: ["internals", "hashing"]
---

# Hashing

Hashing turns a `SignalPackage` into the canonical 32-byte fingerprint
digest. It is the operation that the whole distributed design rests on, and
its overriding requirement is **determinism**: the same package produces the
same digest on any platform, in any build mode, no matter how the features
arrived or in what order they were collected.

The implementation lives across `src/core/hashing/`:

| File | Contents |
| ---- | -------- |
| `feature.zig` | `hashFeature` — hashes one `FeatureValue`, type-tagging it first. |
| `hasher.zig` | `Hasher` — incremental `init` / `add` / `final` over metadata + features. |
| `fingerprint.zig` | `hashFingerprint` / `hashFingerprintBuffer` — hash a whole fingerprint, sorting features first. |

## The three-step recipe

The digest is assembled from three ordered pieces:

1. **Hash the metadata** — schema version, SDK version, collection timestamp.
2. **Sort the features** by `FeatureID` (ascending, numerically).
3. **Hash each feature** — a `u16` feature id, then the SHA-256 of its
   type-tagged value.
4. **Combine** — SHA-256 over the entire stream of the three hash inputs.

All numeric fields are written little-endian, everywhere, so the byte stream
is identical on any architecture.

### 1. Metadata

`Hasher.init(schema_version: u16, sdk_version: []const u8, collected_at: i64)`
seeds the context with:

```
u16 schema_version   (LE)
u32 sdk_version.len  (LE)
sdk_version bytes
i64 collected_at     (LE)
```

The `collected_at` timestamp is an **input**, not a computation — the engine
never reads the clock. It is hashed like any other field, which is what makes
replay possible: a package captured yesterday and replayed today hashes to
the same digest because nothing inside the engine consults today's time.

### 2. Sorting by FeatureID

`hashFingerprint` copies the feature indices, sorts them by
`@intFromEnum(feat.id)` (selection sort, deterministic and allocation-free),
then feeds features in that order. `hashFingerprintBuffer` is the lighter
variant used by the `hash` operation after `format.canonicalize` has already
sorted the slice in place.

Sorting is what makes the digest **independent of collection order**. Without
it, the same set of signals collected in a different order would produce a
different byte stream and therefore a different digest — defeating
determinism and breaking replay. Sorting by the stable numeric `FeatureID`
makes the byte stream canonical regardless of how the features arrived.

### 3. Type-tagging (preventing cross-type collisions)

`hashFeature` hashes a value as a **type-tagged** canonical form. Each
`FeatureValue` variant begins with a distinct one-byte tag:

| Tag | Type |
| --- | ---- |
| `0x01` | Boolean |
| `0x02` | Integer |
| `0x03` | Float |
| `0x04` | String |
| `0x05` | Bytes |
| `0x06` | StringArray |
| `0x07` | IntegerArray |
| `0x08` | FloatArray |
| `0x09` | BytesArray |

The tag guarantees that two features that happen to serialize to the same
bytes at one type never collide at another type. For example, an empty
String (`0x04 00 00 00 00`) and an empty Bytes (`0x05 00 00 00 00`) differ
in their first byte, so they cannot hash to the same digest even though
their payloads agree. The same reasoning protects String vs StringArray,
Integer vs IntegerArray, and so on. Without type-tagging, two different
`FeatureValue` variants could be assigned the same digest, and a cross-type
mistake would silently produce a "matching" but meaningless fingerprint.

Scalar values hash to fixed-width little-endian forms: `Integer` to `i64`,
`Float` to the `u64` bit-cast of the `f64`. String/Bytes and each array
element is prefixed with a `u32` byte-length so boundaries are unambiguous,
then the raw bytes are absorbed.

Each feature in the parent stream is written as:

```
u16 feature_id            (LE)
[32]u8 hashFeature(value) (the type-tagged digest)
```

### 4. Combine

The SHA-256 context absorbs metadata, then each sorted `(id, value-hash)`
pair, then finalizes to the 32-byte digest.

## Incremental hashing

`Hasher` supports absorbing features one at a time without materializing the
whole fingerprint:

```zig
var hasher = core.hashing.Hasher.init(schema_version, sdk_version, collected_at);
try hasher.add(feature.id, feature.value);   // absorbs id + value-hash
try hasher.add(other.id, other.value);
hasher.final(&hash);                          // [32]u8
```

`Hasher.count()` reports the number of features absorbed so far. The caller
is responsible for feeding features in a deterministic order (e.g. sorted by
`FeatureID`); `add` itself does not sort.

## Zig reference (core.hashing)

```zig
const core = @import("core");

// Hash a single feature value (type-tagged, deterministic).
var h: [32]u8 = undefined;
try core.hashing.hashFeature(value, &h);

// Hash an entire fingerprint — sorts by FeatureID, includes metadata.
try core.hashing.hashFingerprint(fp, &h);

// Hash a pre-sorted feature buffer — features only, no metadata.
core.hashing.hashFingerprintBuffer(features, &h);

// Incremental.
var hasher = core.hashing.Hasher.init(2, "0.2.0", 1700000000123);
try hasher.add(FeatureID.UserAgent, .{ .String = "Mozilla/5.0" });
hasher.final(&h);
```

### `hashFeature` (type-tagged)

```zig
const TAG_STRING: u8 = 0x04; // …one constant per FeatureType
pub fn hashFeature(value: FeatureValue, out: *[32]u8) !void {
    var ctx = Sha256.init(.{});
    switch (value) {
        .String => |v| {
            ctx.update(&[_]u8{TAG_STRING});
            var len_buf: [4]u8 = undefined;
            std.mem.writeInt(u32, &len_buf, @intCast(v.len), .little);
            ctx.update(&len_buf);
            ctx.update(v);
        },
        // …every other variant, each starting with its own tag
    }
    ctx.final(out);
}
```

### `Hasher` core loop

```zig
pub fn add(self: *Hasher, id: FeatureID, value: FeatureValue) !void {
    var id_buf: [2]u8 = undefined;
    std.mem.writeInt(u16, &id_buf, @intFromEnum(id), .little);
    self.ctx.update(&id_buf);

    var value_hash: [32]u8 = undefined;
    try hashing.hashFeature(value, &value_hash);
    self.ctx.update(&value_hash);

    self.feature_count += 1;
}
```

### `hashFingerprint` — sort then hash

```zig
pub fn hashFingerprint(fp: Fingerprint, out: *[32]u8) !void {
    var ctx = Sha256.init(.{});

    // 1. Metadata.
    ctx.update(#schema_version_buf(fp.metadata));
    ctx.update(#sdk_bytes(fp.metadata));
    ctx.update(#collected_at_buf(fp.metadata));

    // 2. Sort feature indices by FeatureID…
    //    (selection sort, deterministic, allocation-free)

    // 3. Absorb each feature in sorted order.
    for (sorted_indices) |i| {
        const feat = fp.features[i];
        var id_buf: [2]u8 = undefined;
        std.mem.writeInt(u16, &id_buf, @intFromEnum(feat.id), .little);
        ctx.update(&id_buf);
        var value_hash: [32]u8 = undefined;
        try hashing.hashFeature(feat.value, &value_hash);
        ctx.update(&value_hash);
    }

    ctx.final(out); // 4. Combine → 32-byte digest.
}
```

## Why this is deterministic

- **Little-endian, fixed-width integer writes** — identical bytes on every
  architecture.
- **`Float` via `u64` bit-cast** — no floating-point rounding variation.
- **Explicit sort by `FeatureID`** — no hash-map or collection-order
  dependence (the core never iterates an `AutoHashMap` while hashing).
- **Type-tagging** — no cross-type collisions.
- **No clock, no randomness** — the only time that enters is the hashed
  `collected_at` input.

Any change that shifts the digest of the golden fixture fails the test gate,
so determinism is enforced, not merely claimed. See
[Testing](/docs/internals/testing/) and [Determinism](/docs/concepts/determinism/).
