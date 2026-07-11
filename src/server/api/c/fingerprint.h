/**
 * fingerprint.h — C-compatible API for the Fingerprint Engine native library.
 *
 * Usage:
 *   #include "fingerprint.h"
 *
 *   FingerprintEngine* engine = fingerprint_engine_create();
 *   uint8_t value[1] = {1};
 *   fingerprint_engine_add_feature(engine, FINGERPRINT_FEATURE_COOKIE_ENABLED,
 *                                  FINGERPRINT_TYPE_BOOLEAN, value, 1);
 *   uint8_t digest[32];
 *   int digest_len = 32;
 *   fingerprint_engine_compute(engine, digest, &digest_len);
 *   fingerprint_engine_destroy(engine);
 *
 * Compile with: -lfingerprint (link against libfingerprint.a)
 */

#ifndef FINGERPRINT_ENGINE_H
#define FINGERPRINT_ENGINE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// ── Opaque handle ──

/** Opaque handle to a fingerprint engine instance. */
typedef struct FingerprintEngine FingerprintEngine;

// ── Error codes ──

#define FINGERPRINT_SUCCESS              0
#define FINGERPRINT_ERR_BUFFER_FULL      1
#define FINGERPRINT_ERR_INVALID_FEATURE  2
#define FINGERPRINT_ERR_INVALID_TYPE     3
#define FINGERPRINT_ERR_NOT_INITIALIZED  4

// ── Feature IDs ──

#define FINGERPRINT_FEATURE_COOKIE_ENABLED         0
#define FINGERPRINT_FEATURE_USER_AGENT             1
#define FINGERPRINT_FEATURE_LANGUAGE               2
#define FINGERPRINT_FEATURE_LANGUAGES              3
#define FINGERPRINT_FEATURE_PLATFORM               4
#define FINGERPRINT_FEATURE_VENDOR                 5
#define FINGERPRINT_FEATURE_VENDOR_SUB             6
#define FINGERPRINT_FEATURE_PRODUCT                7
#define FINGERPRINT_FEATURE_PRODUCT_SUB            8
#define FINGERPRINT_FEATURE_APP_NAME               9
#define FINGERPRINT_FEATURE_APP_VERSION           10
#define FINGERPRINT_FEATURE_DO_NOT_TRACK          11
#define FINGERPRINT_FEATURE_HARDWARE_CONCURRENCY  12
#define FINGERPRINT_FEATURE_MAX_TOUCH_POINTS      13
#define FINGERPRINT_FEATURE_DEVICE_MEMORY         14
#define FINGERPRINT_FEATURE_TIMEZONE              15
#define FINGERPRINT_FEATURE_TIMEZONE_OFFSET       16
#define FINGERPRINT_FEATURE_SCREEN_WIDTH          17
#define FINGERPRINT_FEATURE_SCREEN_HEIGHT         18
#define FINGERPRINT_FEATURE_SCREEN_AVAIL_WIDTH    19
#define FINGERPRINT_FEATURE_SCREEN_AVAIL_HEIGHT   20
#define FINGERPRINT_FEATURE_SCREEN_COLOR_DEPTH    21
#define FINGERPRINT_FEATURE_SCREEN_PIXEL_DEPTH    22
#define FINGERPRINT_FEATURE_SCREEN_DPI            23
#define FINGERPRINT_FEATURE_WINDOW_INNER_WIDTH    24
#define FINGERPRINT_FEATURE_WINDOW_INNER_HEIGHT   25
#define FINGERPRINT_FEATURE_WINDOW_OUTER_WIDTH    26
#define FINGERPRINT_FEATURE_WINDOW_OUTER_HEIGHT   27
#define FINGERPRINT_FEATURE_FONTS                28
#define FINGERPRINT_FEATURE_MEDIA_DEVICES         29
#define FINGERPRINT_FEATURE_CANVAS               30
#define FINGERPRINT_FEATURE_WEBGL_VENDOR          31
#define FINGERPRINT_FEATURE_WEBGL_RENDERER        32
#define FINGERPRINT_FEATURE_WEBGL_VERSION         33
#define FINGERPRINT_FEATURE_AUDIO                34
#define FINGERPRINT_FEATURE_CONNECTION_TYPE       35
#define FINGERPRINT_FEATURE_CONNECTION_DOWNLINK   36

// ── Feature types ──

#define FINGERPRINT_TYPE_BOOLEAN       0
#define FINGERPRINT_TYPE_INTEGER       1
#define FINGERPRINT_TYPE_FLOAT         2
#define FINGERPRINT_TYPE_STRING        3
#define FINGERPRINT_TYPE_BYTES         4
#define FINGERPRINT_TYPE_STRING_ARRAY  5
#define FINGERPRINT_TYPE_INTEGER_ARRAY 6
#define FINGERPRINT_TYPE_FLOAT_ARRAY   7
#define FINGERPRINT_TYPE_BYTES_ARRAY   8

// ── Lifecycle ──

/**
 * Creates a new fingerprint engine instance.
 * Returns an opaque handle, or NULL on allocation failure.
 */
FingerprintEngine* fingerprint_engine_create(void);

/**
 * Destroys a fingerprint engine instance and frees all associated memory.
 * Passing NULL is a no-op.
 */
void fingerprint_engine_destroy(FingerprintEngine* engine);

// ── Feature collection ──

/**
 * Adds a feature to the engine.
 *
 * @param engine     Handle from fingerprint_engine_create().
 * @param feature_id One of the FINGERPRINT_FEATURE_* constants.
 * @param value_type One of the FINGERPRINT_TYPE_* constants.
 * @param value_data Pointer to the raw feature value bytes (little-endian).
 * @param value_len  Length of value_data in bytes.
 * @return FINGERPRINT_SUCCESS (0) on success, or an error code.
 */
int fingerprint_engine_add_feature(FingerprintEngine* engine,
                                   int feature_id,
                                   int value_type,
                                   const unsigned char* value_data,
                                   int value_len);

// ── Computation ──

/**
 * Computes the SHA-256 fingerprint digest from all added features.
 * Features are sorted by FeatureID for deterministic output.
 *
 * @param engine     Handle from fingerprint_engine_create().
 * @param out_digest Output buffer for the 32-byte digest.
 * @param out_len    On input: max buffer size. On output: actual digest length.
 * @return FINGERPRINT_SUCCESS (0) on success, or an error code.
 */
int fingerprint_engine_compute(FingerprintEngine* engine,
                               unsigned char* out_digest,
                               int* out_len);

// ── Processing ──

/**
 * Normalizes the fingerprint, checking for type and bounds issues.
 * Returns the number of warnings (0 = clean).
 *
 * @param engine Handle from fingerprint_engine_create().
 * @return Number of normalization warnings, or -1 on error.
 */
int fingerprint_engine_normalize(FingerprintEngine* engine);

/**
 * Computes risk assessment score.
 * Returns 0-100 where 0 = no risk, 100 = high risk.
 *
 * @param engine Handle from fingerprint_engine_create().
 * @return Risk score (0-100), or -1 on error.
 */
int fingerprint_engine_risk(FingerprintEngine* engine);

/**
 * Computes fingerprint entropy.
 * Returns 0-800 where 0 = no entropy, 800 = 8.0 bits/byte * 100.
 *
 * @param engine Handle from fingerprint_engine_create().
 * @return Entropy score (0-800), or -1 on error.
 */
int fingerprint_engine_entropy(FingerprintEngine* engine);

#ifdef __cplusplus
}
#endif

#endif /* FINGERPRINT_ENGINE_H */
