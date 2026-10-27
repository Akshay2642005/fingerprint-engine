// Platform-side ledger for Fingerprint Engine collection events (MongoDB).
//
// Mirror of deploy/ledger/postgres/schema.sql for teams whose platform stores
// in Mongo. One document per collection, fed by the worker's
// `collection_event` AMQP message (ADR-013); the engine never touches a
// database.
//
// Run with: mongosh "<connection-string>" deploy/ledger/mongodb/collection_events.js
//
// Idempotency: `package_id` is the SDK-minted per-collection id (32 lowercase
// hex). The unique index rejects re-delivery; the consumer must treat the
// duplicate-key error (code 11000) as success, exactly like
// `ON CONFLICT DO NOTHING` on the Postgres side.
//
// Timestamps: the envelope carries epoch MILLISECONDS as integers. Convert to
// BSON Date at ingest; `ingress_received_at = 0` means the collection did not
// traverse the ingress, so store null instead of 1970-01-01.

const COLLECTION = "collection_events";

// Validator mirrors the frozen envelope field list and types
// (specs/decisions/0013-event-envelope-ledger-adr.md §2). `stored_at` is
// platform ingest metadata, not part of the wire contract.
const validator = {
	$jsonSchema: {
		bsonType: "object",
		required: [
			"package_id",
			"schema_version",
			"session_id",
			"sdk_version",
			"fingerprint_id",
			"core_digest",
			"core_version",
			"feature_count",
			"core_feature_count",
			"status",
			"entropy",
			"risk",
			"signals",
			"collected_at",
			"stored_at",
		],
		properties: {
			package_id: {
				bsonType: "string",
				pattern: "^[0-9a-f]{32}$",
				description: "SDK-minted 128-bit collection id, lowercase hex; idempotency key",
			},
			schema_version: { bsonType: "int", minimum: 1 },
			session_id: {
				bsonType: "string",
				maxLength: 128,
				description: "x-fpkg-session-id, empty when the client sent none",
			},
			sdk_version: { bsonType: "string", minLength: 1 },
			fingerprint_id: {
				bsonType: "binData",
				description: "full SHA-256 digest (32 bytes)",
			},
			core_digest: {
				bsonType: "binData",
				description: "stable-core SHA-256 digest (32 bytes); a gate, not a verdict",
			},
			core_version: { bsonType: "int", minimum: 1 },
			feature_count: { bsonType: "int", minimum: 0 },
			core_feature_count: { bsonType: "int", minimum: 0 },
			status: {
				bsonType: "int",
				minimum: 0,
				description: "engine Status.code(); 0 = ok",
			},
			entropy: {
				bsonType: ["double", "int"],
				description: "integral values are legal JSON numbers, so accept int as well",
			},
			risk: {
				bsonType: "object",
				required: ["score", "label", "flags"],
				properties: {
					score: { bsonType: ["double", "int"], minimum: 0, maximum: 1 },
					label: { bsonType: "string" },
					flags: { bsonType: "array", items: { bsonType: "string" } },
				},
			},
			signals: {
				bsonType: "object",
				description: "canonicalized values keyed by registry feature name",
			},
			collected_at: { bsonType: "date" },
			ingress_received_at: {
				bsonType: ["date", "null"],
				description: "null when the collection did not traverse the ingress",
			},
			stored_at: { bsonType: "date" },
		},
	},
};

if (!db.getCollectionNames().includes(COLLECTION)) {
	db.createCollection(COLLECTION, {
		validator,
		validationLevel: "strict",
		validationAction: "error",
	});
} else {
	db.runCommand({ collMod: COLLECTION, validator, validationLevel: "strict", validationAction: "error" });
}

// Idempotency: one document per SDK-minted collection id.
db.getCollection(COLLECTION).createIndex(
	{ package_id: 1 },
	{ unique: true, name: "package_id_unique" },
);

// Continuity / investigation lookups (ADR-013 §2).
db.getCollection(COLLECTION).createIndex(
	{ fingerprint_id: 1 },
	{ name: "fingerprint_id_1" },
);
db.getCollection(COLLECTION).createIndex(
	{ session_id: 1 },
	{ name: "session_id_1", partialFilterExpression: { session_id: { $gt: "" } } },
);
db.getCollection(COLLECTION).createIndex(
	{ collected_at: -1 },
	{ name: "collected_at_-1" },
);
db.getCollection(COLLECTION).createIndex(
	{ ingress_received_at: -1 },
	{ name: "ingress_received_at_-1", partialFilterExpression: { ingress_received_at: { $type: "date" } } },
);

// Agent/workspace queries over signal values. A wildcard index makes *every*
// signal key queryable without declaring each registry name; per-name indexes
// can replace it for the few keys a workspace filters on most.
db.getCollection(COLLECTION).createIndex(
	{ "signals.$**": 1 },
	{ name: "signals_wildcard" },
);
