/**
 * SignalPackage v2 binary serializer (D14).
 *
 * Mirrors src/serialization/binary.zig byte-for-byte so the browser output
 * is accepted verbatim by the ingress/worker pipeline. Wire contract in
 * specs/rework/DESIGN.md §9.4.4; cross-checked against the Zig golden
 * fixture by the TS parity test (tests/clients/browser/).
 *
 * Pure functions, no clocks, no globals — fully replayable.
 */

import type { Signal, SignalPackageOptions } from "./types.js";
import { FeatureType } from "./generated/tables.js";

/** Binary format magic bytes: "FNGR" (matches serialization/binary.zig). */
export const MAGIC = "FNGR";

/** SignalPackage body schema version (matches codec.schema_version_v2). */
export const SCHEMA_VERSION = 2;

const textEncoder = new TextEncoder();

/** 16 random bytes for replay identity (v4-UUID-shaped optional). */
export function newPackageId(): Uint8Array {
	const id = new Uint8Array(16);
	if (typeof crypto !== "undefined" && typeof crypto.getRandomValues === "function") {
		crypto.getRandomValues(id);
	} else {
		// Non-secure fallback (file://, http on old browsers). Documented as
		// weaker; ingress/worker treat the id as correlation, not entropy.
		for (let i = 0; i < 16; i++) id[i] = Math.floor(Math.random() * 256);
	}
	return id;
}

/** Lowercase hex of bytes. */
export function toHex(bytes: Uint8Array): string {
	let out = "";
	for (let i = 0; i < bytes.length; i++) {
		out += bytes[i].toString(16).padStart(2, "0");
	}
	return out;
}

/** Growable little-endian byte writer. */
class ByteWriter {
	#buf: Uint8Array;
	#view: DataView;
	#len = 0;

	constructor(capacity = 4096) {
		this.#buf = new Uint8Array(capacity);
		this.#view = new DataView(this.#buf.buffer);
	}

	#ensure(extra: number): void {
		const needed = this.#len + extra;
		if (needed <= this.#buf.byteLength) return;
		let cap = this.#buf.byteLength * 2;
		while (cap < needed) cap *= 2;
		const next = new Uint8Array(cap);
		next.set(this.#buf.subarray(0, this.#len));
		this.#buf = next;
		this.#view = new DataView(next.buffer);
	}

	u8(v: number): void {
		this.#ensure(1);
		this.#view.setUint8(this.#len, v);
		this.#len += 1;
	}

	u16(v: number): void {
		this.#ensure(2);
		this.#view.setUint16(this.#len, v, true);
		this.#len += 2;
	}

	u32(v: number): void {
		this.#ensure(4);
		this.#view.setUint32(this.#len, v >>> 0, true);
		this.#len += 4;
	}

	i64(v: number): void {
		this.#ensure(8);
		this.#view.setBigInt64(this.#len, BigInt(Math.trunc(v)), true);
		this.#len += 8;
	}

	f64(v: number): void {
		this.#ensure(8);
		this.#view.setFloat64(this.#len, v, true);
		this.#len += 8;
	}

	bytes(b: Uint8Array): void {
		this.#ensure(b.byteLength);
		this.#buf.set(b, this.#len);
		this.#len += b.byteLength;
	}

	/** Detaches the internal buffer; the writer must not be reused. */
	finish(): Uint8Array {
		return this.#buf.slice(0, this.#len);
	}
}

/** Serializes a SignalPackage v2 body (MAGIC | schema | ... | TLV ×N). */
export function encodeSignalPackage(
	signals: Signal[],
	opts: SignalPackageOptions,
): Uint8Array {
	if (signals.length > 0xffff) {
		throw new RangeError("too many signals: " + signals.length + " (max 65535)");
	}

	const sdk = textEncoder.encode(opts.sdkVersion);
	if (sdk.byteLength > 0xffff) {
		throw new RangeError("sdk_version too long");
	}

	const w = new ByteWriter(4096 + sdk.byteLength + signals.length * 16);
	w.bytes(textEncoder.encode(MAGIC));
	w.u16(SCHEMA_VERSION);
	w.u16(sdk.byteLength);
	w.bytes(sdk);
	w.i64(opts.collectedAt);
	w.bytes(opts.packageId);
	w.u16(signals.length);

	for (const signal of signals) {
		writeFeature(w, signal);
	}
	return w.finish();
}

function writeFeature(w: ByteWriter, signal: Signal): void {
	if (signal.id > 0xffff) throw new RangeError("feature id out of range: " + signal.id);
	w.u16(signal.id);
	w.u8(signal.type);

	// Payload is encoded into its own writer so its length is known before
	// the u32 length prefix is written (matches binary.zig's fixed buffer).
	const payload = new ByteWriter(64);
	writePayload(payload, signal);
	const encoded = payload.finish();
	if (encoded.byteLength > 0xffffffff) {
		throw new RangeError("feature payload too large");
	}
	w.u32(encoded.byteLength);
	w.bytes(encoded);
}

function writePayload(w: ByteWriter, signal: Signal): void {
	switch (signal.type) {
		case FeatureType.Boolean:
			w.u8(signal.value ? 1 : 0);
			break;
		case FeatureType.Integer:
			w.i64(signal.value as number);
			break;
		case FeatureType.Float:
			w.f64(signal.value as number);
			break;
		case FeatureType.String: {
			const b = textEncoder.encode(signal.value as string);
			w.u32(b.byteLength);
			w.bytes(b);
			break;
		}
		case FeatureType.Bytes: {
			const b = signal.value as Uint8Array;
			w.u32(b.byteLength);
			w.bytes(b);
			break;
		}
		case FeatureType.StringArray: {
			const items = signal.value as string[];
			w.u32(items.length);
			for (const item of items) {
				const b = textEncoder.encode(item);
				w.u32(b.byteLength);
				w.bytes(b);
			}
			break;
		}
		case FeatureType.IntegerArray: {
			const items = signal.value as number[];
			w.u32(items.length);
			for (const item of items) w.i64(item);
			break;
		}
		case FeatureType.FloatArray: {
			const items = signal.value as number[];
			w.u32(items.length);
			for (const item of items) w.f64(item);
			break;
		}
		case FeatureType.BytesArray: {
			const items = signal.value as unknown as Uint8Array[];
			w.u32(items.length);
			for (const item of items) {
				w.u32(item.byteLength);
				w.bytes(item);
			}
			break;
		}
		default:
			throw new TypeError("unknown feature type: " + signal.type);
	}
}
