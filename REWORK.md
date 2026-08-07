You are a Principal Zig Architect and Distributed Systems Engineer.

You are NOT modernizing code.

You are redesigning an entire distributed computation engine.

==========================================================
PROJECT
==========================================================

Repository:
Fingerprint Engine

Language:
Zig

Current Zig Version:
0.16.0

Target Zig Version:
0.14.1

The downgrade is intentional.

The project currently builds:

- Browser WASM
- Native Static Library
- Future SDKs

The project is NOT a backend.

It is NOT a microservice.

It is NOT tied to RabbitMQ.

It is NOT tied to Go.

It is a reusable deterministic computation engine.

==========================================================
CURRENT RESPONSIBILITIES
==========================================================

Current engine:

- feature registry
- fingerprint model
- normalization
- validation
- serialization
- hashing
- similarity
- entropy
- risk primitives
- browser WASM exports
- native C ABI

Current browser:

Browser

↓

Collectors

↓

Fingerprint Generation

↓

Hash

↓

Send Fingerprint

This architecture is deprecated.

==========================================================
NEW GOAL
==========================================================

The engine must become a distributed deterministic computation engine.

The browser must NEVER generate the canonical fingerprint.

Instead:

Browser

↓

Collectors

↓

WASM

↓

Validation

↓

Normalization

↓

Serialization

↓

Integrity

↓

Signal Package

↓

Ingress Service

↓

RabbitMQ

↓

Distributed Fingerprint Workers

↓

Canonical Fingerprint

↓

Fraud Platform

The Zig engine only performs deterministic computation.

==========================================================
ABSOLUTE RULES
==========================================================

The Zig engine must NEVER know about:

RabbitMQ

Kafka

HTTP

REST

gRPC

NATS

WebSockets

Databases

Authentication

Users

Organizations

Policies

Business Logic

Network Protocols

No transport-specific code inside core.

==========================================================
ENGINE API
==========================================================

The engine should expose deterministic APIs only.

Example:

process()

normalize()

validate()

hash()

entropy()

similarity()

risk()

serialize()

deserialize()

No networking.

No sockets.

No queues.

==========================================================
NEW ARCHITECTURE
==========================================================

The repository must be reorganized into clear layers.

Example:

src/

core/
engine/
model/
features/
normalization/
serialization/
hashing/
entropy/
similarity/
risk/
validation/

runtime/

io/

adapter/

browser/

native/

worker/

sdk/

tools/

tests/

The exact layout is up to you.

==========================================================
CORE PRINCIPLE
==========================================================

Everything must depend inward.

Nothing depends outward.

Adapters depend on Engine.

Engine depends on Core.

Core depends on nothing.

==========================================================
TRANSPORT ABSTRACTION
==========================================================

Create a custom IO abstraction.


Design a minimal interface.

Something conceptually similar to

Reader

Writer

Message

Buffer

Allocator

Frame

Transport

Dispatcher

Engine

Completion

Event

Command

Request

Response

The engine should receive a Request object.

The adapter constructs the Request.

The adapter owns RabbitMQ.

The engine does not.

==========================================================
AMQP ADAPTER
==========================================================

Implement an adapter layer.

RabbitMQ Adapter

↓

Decode Message

↓

Convert to Engine Request

↓

Engine.process()

↓

Engine Result

↓

Encode Message

↓

Publish

The adapter owns:

AMQP

Exchange

Routing Keys

Queues

Reconnect

Retry

Dead Letter Queue

Backoff

Publisher Confirms

Consumer

Everything AMQP-specific stays outside the engine.

==========================================================
MESSAGE DESIGN
==========================================================

Design immutable messages.

Example

SignalPackage

FingerprintResult

Diagnostics

Metadata

FingerprintComputed

ValidationResult

RiskResult

SimilarityResult

Everything versioned.

Everything deterministic.

==========================================================
SERIALIZATION
==========================================================

Current serialization exists.

Redesign it.

Support

Binary

JSON

Future Protobuf

Future FlatBuffers

Future Cap'n Proto

Design serialization interfaces.

==========================================================
WORKERS
==========================================================

Worker executable.

Very small.

Pseudo flow:

Receive Message

↓

Deserialize

↓

Engine.process()

↓

Serialize

↓

Publish

Worker should contain almost no business logic.

==========================================================
WASM
==========================================================

The browser WASM must change responsibilities.

Remove:

Canonical fingerprint generation

Instead provide

Validation

Normalization

Serialization

Diagnostics

Integrity

Packaging

Collection helpers

Optional lightweight risk

==========================================================
NATIVE LIBRARY
==========================================================

Native exports become deterministic APIs only.

No transport.

No worker logic.

Only engine functions.

==========================================================
CUSTOM IO
==========================================================


Not copied.

The project should define:

Buffer

Message

Frame

Request

Response

Channel

Dispatcher

Reader

Writer

Pipeline

Completion

Ring Buffer

Command

Operation

Executor

Everything transport-independent.

==========================================================
DESIGN GOALS
==========================================================

Stateless

Deterministic

Replayable

Zero-copy where possible

Arena allocation

Minimal allocations

Cache-friendly

SIMD-ready

Portable

No global mutable state

Explicit ownership

No hidden allocations

==========================================================
EVENT FLOW
==========================================================

Browser

↓

Collectors

↓

Validation

↓

Normalization

↓

Packaging

↓

Ingress

↓

RabbitMQ

↓

Worker

↓

Engine.process()

↓

Fingerprint

↓

Risk

↓

Metadata

↓

FingerprintComputed

==========================================================
ZIG DOWNGRADE
==========================================================

Target Zig version:

0.14.1

Everything must compile cleanly on Zig 0.14.1.

Update:

build.zig

build APIs

std usage

allocator APIs

module APIs

imports

test APIs

Remove any APIs introduced after 0.14.

==========================================================
TESTING
==========================================================

Keep all existing tests.

Add tests for

Engine

IO

Serialization

Worker

Request

Response

AMQP codec

Version compatibility

Replay

Determinism

==========================================================
DOCUMENTATION
==========================================================

Generate

Architecture.md

Engine.md

IO.md

Worker.md

AMQP.md

Serialization.md

Migration.md

Design.md

==========================================================
DELIVERABLES
==========================================================

DO NOT immediately generate code.

Phase 1

Analyze the existing repository.

Explain every module.

Explain every dependency.

Find coupling.

Find transport assumptions.

Find browser assumptions.

==========================================================

Phase 2

Design the new architecture.

Produce diagrams.

Module layout.

Dependency graph.

Worker architecture.

IO architecture.

AMQP architecture.

==========================================================

Phase 3

Produce a migration plan.

Old → New mapping.

File moves.

Renames.

Deleted modules.

New modules.

==========================================================

Phase 4

Only after architecture approval,

begin implementation incrementally.

Never rewrite the repository at once.

Each commit must compile.

Each commit must pass tests.

Migration must remain bisectable.
