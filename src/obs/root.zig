//! Observability leaf module (ADR-014, story m8-observability).
//!
//! Depends only on std (and io, for the scrape listener) — never on engine,
//! adapter, or cmd — so both executables can import it without inverting the
//! layering (ADR-002).
//!
//! - `metrics` — comptime-declared, atomic, allocation-free registry and the
//!   Prometheus text renderer.
//! - `scrape` — the GET-only `/metrics` + `/readyz` listener that serves it.

pub const metrics = @import("metrics.zig");
