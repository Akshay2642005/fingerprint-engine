/**
 * fingerprint.h — C-compatible API for the Fingerprint Engine native library.
 *
 * Usage:
 *   #include "fingerprint.h"
 *
 *   FingerprintEngine* engine = fingerprint_engine_create();
 *   fingerprint_engine_add_string(engine, FINGERPRINT_FEATURE_USER_AGENT,
 *                                  "Mozilla/5.0...", 14);
 *   uint8_t digest[32];
 *   fingerprint_engine_compute(engine, digest);
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

typedef struct FingerprintEngine FingerprintEngine;

// ── Error codes ──

#define FINGERPRINT_SUCCESS              0
#define FINGERPRINT_ERR_BUFFER_FULL      1
#define FINGERPRINT_ERR_INVALID_FEATURE  2
#define FINGERPRINT_ERR_INVALID_TYPE     3
#define FINGERPRINT_ERR_NOT_INITIALIZED  4
#define FINGERPRINT_ERR_INVALID_INPUT    5

// ── Feature IDs (must match Zig model.zig exactly) ──

// Navigator (0-16)
#define FINGERPRINT_FEATURE_USER_AGENT              0
#define FINGERPRINT_FEATURE_LANGUAGE                1
#define FINGERPRINT_FEATURE_LANGUAGES               2
#define FINGERPRINT_FEATURE_PLATFORM                3
#define FINGERPRINT_FEATURE_VENDOR                  4
#define FINGERPRINT_FEATURE_PRODUCT                 5
#define FINGERPRINT_FEATURE_PRODUCT_SUB             6
#define FINGERPRINT_FEATURE_APP_NAME                7
#define FINGERPRINT_FEATURE_APP_VERSION             8
#define FINGERPRINT_FEATURE_COOKIE_ENABLED          9
#define FINGERPRINT_FEATURE_DO_NOT_TRACK           10
#define FINGERPRINT_FEATURE_HARDWARE_CONCURRENCY   11
#define FINGERPRINT_FEATURE_MAX_TOUCH_POINTS       12
#define FINGERPRINT_FEATURE_DEVICE_MEMORY          13
#define FINGERPRINT_FEATURE_PDF_VIEWER_ENABLED     14
#define FINGERPRINT_FEATURE_VENDOR_SUB             15
#define FINGERPRINT_FEATURE_DEVICE_RAM             16

// Screen (17-28)
#define FINGERPRINT_FEATURE_SCREEN_WIDTH           17
#define FINGERPRINT_FEATURE_SCREEN_HEIGHT          18
#define FINGERPRINT_FEATURE_AVAILABLE_WIDTH        19
#define FINGERPRINT_FEATURE_AVAILABLE_HEIGHT       20
#define FINGERPRINT_FEATURE_COLOR_DEPTH            21
#define FINGERPRINT_FEATURE_PIXEL_DEPTH            22
#define FINGERPRINT_FEATURE_DEVICE_PIXEL_RATIO     23
#define FINGERPRINT_FEATURE_INNER_WIDTH            24
#define FINGERPRINT_FEATURE_INNER_HEIGHT           25
#define FINGERPRINT_FEATURE_OUTER_WIDTH            26
#define FINGERPRINT_FEATURE_OUTER_HEIGHT           27
#define FINGERPRINT_FEATURE_SCREEN_ORIENTATION     28

// Hardware (29-34)
#define FINGERPRINT_FEATURE_CPU_CLASS              29
#define FINGERPRINT_FEATURE_CPU_CORES              30
#define FINGERPRINT_FEATURE_CPU_ARCHITECTURE       31
#define FINGERPRINT_FEATURE_PLATFORM_ARCHITECTURE  32
#define FINGERPRINT_FEATURE_HARDWARE_ACCELERATION  33
#define FINGERPRINT_FEATURE_TOUCH_SUPPORT          34

// Canvas (35)
#define FINGERPRINT_FEATURE_CANVAS_HASH            35

// WebGL (36-42)
#define FINGERPRINT_FEATURE_WEBGL_VENDOR           36
#define FINGERPRINT_FEATURE_WEBGL_RENDERER         37
#define FINGERPRINT_FEATURE_WEBGL_VERSION          38
#define FINGERPRINT_FEATURE_WEBGL_HASH             39
#define FINGERPRINT_FEATURE_WEBGL_EXTENSIONS       40
#define FINGERPRINT_FEATURE_WEBGL_PARAMETERS       41
#define FINGERPRINT_FEATURE_WEBGL_SHADER_PRECISION 42

// Audio (43)
#define FINGERPRINT_FEATURE_AUDIO_HASH             43

// Fonts (44)
#define FINGERPRINT_FEATURE_FONTS_HASH             44

// Platform (45-46)
#define FINGERPRINT_FEATURE_OPERATING_SYSTEM       45
#define FINGERPRINT_FEATURE_OS_VERSION             46

// Storage (47-51)
#define FINGERPRINT_FEATURE_LOCAL_STORAGE          47
#define FINGERPRINT_FEATURE_SESSION_STORAGE        48
#define FINGERPRINT_FEATURE_INDEXED_DB              49
#define FINGERPRINT_FEATURE_CACHE_STORAGE          50
#define FINGERPRINT_FEATURE_COOKIES_ENABLED        51

// Permissions (52-55)
#define FINGERPRINT_FEATURE_NOTIFICATION_PERMISSION    52
#define FINGERPRINT_FEATURE_GEOLOCATION_PERMISSION     53
#define FINGERPRINT_FEATURE_CAMERA_PERMISSION          54
#define FINGERPRINT_FEATURE_MICROPHONE_PERMISSION      55

// Media (56-61)
#define FINGERPRINT_FEATURE_AUDIO_INPUT_DEVICES    56
#define FINGERPRINT_FEATURE_AUDIO_OUTPUT_DEVICES   57
#define FINGERPRINT_FEATURE_VIDEO_INPUT_DEVICES    58
#define FINGERPRINT_FEATURE_SUPPORTED_CODECS       59
#define FINGERPRINT_FEATURE_MEDIA_FORMATS          60
#define FINGERPRINT_FEATURE_AUDIO_FORMATS          61

// Network (62-66)
#define FINGERPRINT_FEATURE_CONNECTION_TYPE        62
#define FINGERPRINT_FEATURE_CONNECTION_DOWNLINK    63
#define FINGERPRINT_FEATURE_CONNECTION_EFFECTIVE_TYPE 64
#define FINGERPRINT_FEATURE_CONNECTION_RTT         65
#define FINGERPRINT_FEATURE_CONNECTION_SAVE_DATA   66

// Locale & Timezone (67-70)
#define FINGERPRINT_FEATURE_LOCALE                 67
#define FINGERPRINT_FEATURE_TIMEZONE               68
#define FINGERPRINT_FEATURE_TIMEZONE_OFFSET        69
#define FINGERPRINT_FEATURE_DATE_TIME_FORMAT       70

// Battery (71-73)
#define FINGERPRINT_FEATURE_BATTERY_LEVEL          71
#define FINGERPRINT_FEATURE_BATTERY_CHARGING       72
#define FINGERPRINT_FEATURE_BATTERY_CHARGING_TIME  73

// Media Capabilities (74-76)
#define FINGERPRINT_FEATURE_DECODE_CAPABILITY      74
#define FINGERPRINT_FEATURE_ENCODE_CAPABILITY      75
#define FINGERPRINT_FEATURE_HDR_SUPPORT            76

// Crypto (77-78)
#define FINGERPRINT_FEATURE_CRYPTO_SUPPORT         77
#define FINGERPRINT_FEATURE_SUBTLE_CRYPTO          78

// Speech (79)
#define FINGERPRINT_FEATURE_SPEECH_SYNTHESIS_VOICES 79

// GPU (80-82)
#define FINGERPRINT_FEATURE_GPU_VENDOR             80
#define FINGERPRINT_FEATURE_GPU_RENDERER           81
#define FINGERPRINT_FEATURE_GPU_DRIVER_VERSION     82

// Performance (83-85)
#define FINGERPRINT_FEATURE_HW_CONC_PERF           83
#define FINGERPRINT_FEATURE_DEV_MEM_PERF           84
#define FINGERPRINT_FEATURE_TIME_PRECISION         85

// CSS (86-90)
#define FINGERPRINT_FEATURE_CSS_CUSTOM_PROPERTIES  86
#define FINGERPRINT_FEATURE_CSS_GRID_SUPPORT       87
#define FINGERPRINT_FEATURE_CSS_FLEXBOX_SUPPORT    88
#define FINGERPRINT_FEATURE_CSS_CONTAINER_QUERY    89
#define FINGERPRINT_FEATURE_CSS_HAS_SELECTOR       90

// Browser Features (91-95)
#define FINGERPRINT_FEATURE_SERVICE_WORKER_SUPPORT 91
#define FINGERPRINT_FEATURE_WEB_WORKER_SUPPORT     92
#define FINGERPRINT_FEATURE_SHARED_WORKER_SUPPORT  93
#define FINGERPRINT_FEATURE_WEBSOCKET_SUPPORT      94
#define FINGERPRINT_FEATURE_WEBRTC_SUPPORT         95

// Input (96-98)
#define FINGERPRINT_FEATURE_KEYBOARD_LAYOUT        96
#define FINGERPRINT_FEATURE_POINTER_EVENTS         97
#define FINGERPRINT_FEATURE_GAMEPAD_SUPPORT        98

// Metadata (99-101)
#define FINGERPRINT_FEATURE_SCHEMA_VERSION         99
#define FINGERPRINT_FEATURE_SDK_VERSION           100
#define FINGERPRINT_FEATURE_COLLECTION_TIMESTAMP  101

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

FingerprintEngine* fingerprint_engine_create(void);
void fingerprint_engine_destroy(FingerprintEngine* engine);

// ── Feature collection ──

void fingerprint_engine_add_boolean(FingerprintEngine* engine, int feature_id, int value);
void fingerprint_engine_add_integer(FingerprintEngine* engine, int feature_id, int64_t value);
void fingerprint_engine_add_float(FingerprintEngine* engine, int feature_id, double value);
int fingerprint_engine_add_string(FingerprintEngine* engine, int feature_id,
                                  const char* value, int value_len);
int fingerprint_engine_add_bytes(FingerprintEngine* engine, int feature_id,
                                 const unsigned char* value, int value_len);

// ── Computation ──

int fingerprint_engine_compute(FingerprintEngine* engine, unsigned char* out_digest);

// ── Processing ──

int fingerprint_engine_normalize(FingerprintEngine* engine);
int fingerprint_engine_risk(FingerprintEngine* engine);
int fingerprint_engine_entropy(FingerprintEngine* engine);

#ifdef __cplusplus
}
#endif

#endif /* FINGERPRINT_ENGINE_H */
