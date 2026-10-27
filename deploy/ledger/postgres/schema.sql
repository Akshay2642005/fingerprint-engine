-- Platform-side ledger for Fingerprint Engine collection events.
--
-- One row per collection, fed by the worker's `collection_event` AMQP message
-- (ADR-013). The engine never touches a database: this schema is owned by the
-- consuming platform. Every column maps 1:1 to a field of the frozen envelope
-- (specs/decisions/0013-event-envelope-ledger-adr.md §2), so ingestion is a
-- parse + insert, never a re-join with the live `result.*` fanout.
--
-- Idempotency: `package_id` is the SDK-minted per-collection id and is the
-- primary key. Re-delivery is handled with
--   INSERT ... ON CONFLICT (package_id) DO NOTHING
-- which makes the consumer safe under at-least-once delivery.
--
-- Timestamps: the envelope carries epoch MILLISECONDS as integers. The
-- consumer converts them before insert:
--   to_timestamp(collected_at_ms / 1000.0),
--   to_timestamp(ingress_received_at_ms / 1000.0)  -- NULL when 0
-- `ingress_received_at_ms = 0` means the collection did not traverse the
-- ingress (direct TCP/loopback client); store NULL rather than 1970.
--
-- Signals are stored as JSONB keyed by registry feature name (ADR-012: a name
-- is stable once published; reuse is a breaking change). They can contain
-- device-identifying values: apply the platform's encryption-at-rest and
-- access policy, and never expose the raw column to unauthenticated callers.

CREATE TABLE IF NOT EXISTS collection_events (
    -- Ledger identity / idempotency key.
    package_id          uuid        PRIMARY KEY,

    -- Envelope metadata.
    schema_version      smallint    NOT NULL,
    session_id          text        NOT NULL DEFAULT '',
    sdk_version         text        NOT NULL,

    -- Digests: `fingerprint_id` is the full SHA-256, `core_digest` the
    -- stable-core gate (D-v1-5). Both are 32 bytes.
    fingerprint_id      bytea       NOT NULL,
    core_digest         bytea       NOT NULL,
    core_version        smallint    NOT NULL,
    feature_count       smallint    NOT NULL,
    core_feature_count  smallint    NOT NULL,

    -- Engine outcome and evaluation outputs.
    status              smallint    NOT NULL,
    entropy             double precision NOT NULL,
    risk                jsonb       NOT NULL,

    -- Canonicalized feature values, keyed by registry name.
    signals             jsonb       NOT NULL,

    -- Collection timestamps (converted from the envelope's epoch ms).
    collected_at        timestamptz NOT NULL,
    ingress_received_at timestamptz,

    -- Platform ingest time, for lag/SLO reporting; not part of the contract.
    stored_at           timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT collection_events_fingerprint_id_len CHECK (octet_length(fingerprint_id) = 32),
    CONSTRAINT collection_events_core_digest_len CHECK (octet_length(core_digest) = 32),
    CONSTRAINT collection_events_risk_shape CHECK (
        jsonb_typeof(risk -> 'score') = 'number'
        AND jsonb_typeof(risk -> 'label') = 'string'
        AND jsonb_typeof(risk -> 'flags') = 'array'
    ),
    CONSTRAINT collection_events_signals_shape CHECK (jsonb_typeof(signals) = 'object')
);

-- Continuity/investigation lookups (ADR-013 §2): "which collections share this
-- fingerprint / session, and when".
CREATE INDEX IF NOT EXISTS collection_events_fingerprint_id_idx
    ON collection_events (fingerprint_id);

CREATE INDEX IF NOT EXISTS collection_events_session_id_idx
    ON collection_events (session_id)
    WHERE session_id <> '';

CREATE INDEX IF NOT EXISTS collection_events_collected_at_idx
    ON collection_events (collected_at DESC);

CREATE INDEX IF NOT EXISTS collection_events_ingress_received_at_idx
    ON collection_events (ingress_received_at DESC)
    WHERE ingress_received_at IS NOT NULL;

-- Agent/workspace queries over signal values. `jsonb_path_ops` is smaller and
-- faster than the default opclass for the containment (`@>`) queries this
-- surface uses; use the default opclass instead if key-existence (`?`) queries
-- become common.
CREATE INDEX IF NOT EXISTS collection_events_signals_gin
    ON collection_events USING gin (signals jsonb_path_ops);

-- Optional: dedupe-by-fingerprint helper for identity anchoring (M7.1), which
-- is platform logic and deliberately not an engine concern.
-- CREATE INDEX collection_events_fingerprint_core_idx
--     ON collection_events (fingerprint_id, core_digest, collected_at DESC);
