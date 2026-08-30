---
title: "FPKG Frame"
description: "The FPKG envelope: 48-byte header (magic, envelope v1, message type, codec, payload length, integrity digest) framing every wire message."
category: "reference"
order: 5
crumbs: ["reference", "fpkp-frame"]
---

# FPKG Frame

Every message that crosses a transport boundary — the SDK↔ingress↔worker hop
and the worker→fraud-platform AMQP events — is wrapped in the **FPKG
envelope**. It is the wire unit that carries a payload together with its
framing and integrity metadata. The implementation lives in
`src/io/frame.zig`; the engine itself never frames or unframes, so the core
stays transport-free.

The frame is a fixed **48-byte header** followed by the payload. All integer
fields are **little-endian**.

## Header layout (48 bytes)

| Offset | Size | Field | Meaning |
| ------ | ---- | ----- | ------- |
| 0 | 4 | `magic` | ASCII `"FPKG"`. |
| 4 | 2 | `version` | Envelope version (`1`). |
| 6 | 1 | `message_type` | FPKG message-type enum (`u8`). |
| 7 | 1 | `codec` | Payload codec selector (`u8`). |
| 8 | 4 | `payload_len` | Payload length in bytes (`u32`). |
| 12 | 4 | `reserved` | Reserved `u32`, must be zero. |
| 16 | 32 | `integrity` | SHA-256 of the payload. |
| 48 | — | payload | `payload_len` bytes. |

`reserved` must be `0`; a non-zero value is rejected as `InvalidReserved`
because future versions will use it for flags and a non-zero value from an
older peer is a protocol error.

## Message types

The `message_type` field is the FPKG `MessageType` enum (`u8`):

| Tag | Message type | Direction |
| --- | ------------ | --------- |
| 1 | `signal_package` | request (canonical path → `hash`) |
| 2 | `validation_result` | request / reply |
| 3 | `normalization_result` | request / reply |
| 4 | `fingerprint_result` | request / reply |
| 5 | `risk_result` | request / reply |
| 6 | `similarity_result` | request / reply |
| 7 | `diagnostics` | outbound-only |
| 8 | `fingerprint_computed` | outbound-only |
| 9 | `entropy_result` | outbound-only |

Unknown `message_type` tags are rejected as `InvalidMessageType`. The
worker maps select inbound types to engine operations (see
[Operations](/docs/reference/operations/)); the outbound-only types
(`diagnostics`, `fingerprint_computed`, `entropy_result`) are not dispatched
as operations.

## Codec selector

The `codec` field (the FPKG `Codec` enum, mirroring `CodecID` in
`src/serialization/codec.zig`) selects how the payload is encoded:

| Tag | Codec | Meaning |
| --- | ----- | ------- |
| 1 | `binary` | The default: the versioned TLV binary body. |
| 2 | `json` | JSON encoding. |

Unknown codecs are rejected as `InvalidCodec`. The interface is extensible;
future codecs (protobuf, flatbuffers, cap'n proto) plug in behind the same
selector without renumbering existing tags.

## Integrity (tamper-evidence, not authenticity)

`integrity` is the **SHA-256 digest of the canonical serialized payload**.
It proves that the payload is exactly what it was when the digest was
computed — it detects tampering and corruption — but it is **not
authenticity**: there are no keys in the engine, so the digest does not
prove who produced the frame. Any actor can recompute a valid SHA-256 of a
modified payload; integrity is about detecting accidental or casual change,
not about defending against a malicious producer.

`FrameHeader.integrityOf(payload)` computes the digest; `integrityValid`
compares it against the header's field. The same algorithm is mirrored in
`src/serialization/integrity.zig` so serialization stays transport-free.

## Envelope versioning

`current_version` is `1`. `FrameHeader.decode` rejects frames whose
`version != current_version` as `UnsupportedVersion` — before parsing
anything else, so a worker can reject an unknown-envelope peer without
misreading its payload. This is one of the two version gates (the other is
the SignalPackage body schema version, at the engine boundary; see
[Serialization](/docs/internals/serialization/)).

## Worker reply

A worker reply is an FPKG frame whose payload is `u8 status | engine
result` — the first byte is the engine `Status` (see [Status](/docs/reference/status/)).
For a successful `hash`, that is `0` followed by the 32-byte digest, the
`u16` feature count, and the `u16` schema version.
