"""
Type definitions mirroring the Zig core types.

These enums and constants match FeatureID, FeatureType, and ErrorCode
from the native library (src/core/features/model.zig, src/server/native/root.zig).
"""

from enum import IntEnum


class FeatureID(IntEnum):
    """37 browser fingerprint signals matching src/core/features/model.zig."""

    # Navigator signals
    COOKIE_ENABLED = 0
    USER_AGENT = 1
    LANGUAGE = 2
    LANGUAGES = 3
    PLATFORM = 4
    VENDOR = 5
    VENDOR_SUB = 6
    PRODUCT = 7
    PRODUCT_SUB = 8
    APP_NAME = 9
    APP_VERSION = 10
    DO_NOT_TRACK = 11
    HARDWARE_CONCURRENCY = 12
    MAX_TOUCH_POINTS = 13
    DEVICE_MEMORY = 14
    TIMEZONE = 15
    TIMEZONE_OFFSET = 16

    # Screen signals
    SCREEN_WIDTH = 17
    SCREEN_HEIGHT = 18
    SCREEN_AVAIL_WIDTH = 19
    SCREEN_AVAIL_HEIGHT = 20
    SCREEN_COLOR_DEPTH = 21
    SCREEN_PIXEL_DEPTH = 22
    SCREEN_DPI = 23

    # Window signals
    WINDOW_INNER_WIDTH = 24
    WINDOW_INNER_HEIGHT = 25
    WINDOW_OUTER_WIDTH = 26
    WINDOW_OUTER_HEIGHT = 27

    # Font & media signals
    FONTS = 28
    MEDIA_DEVICES = 29

    # Canvas & WebGL
    CANVAS = 30
    WEBGL_VENDOR = 31
    WEBGL_RENDERER = 32
    WEBGL_VERSION = 33

    # Audio & network
    AUDIO = 34
    CONNECTION_TYPE = 35
    CONNECTION_DOWNLINK = 36


class FeatureType(IntEnum):
    """9 value types matching src/core/features/model.zig."""

    BOOLEAN = 0
    INTEGER = 1
    FLOAT = 2
    STRING = 3
    BYTES = 4
    STRING_ARRAY = 5
    INTEGER_ARRAY = 6
    FLOAT_ARRAY = 7
    BYTES_ARRAY = 8


class ErrorCode(IntEnum):
    """Error codes matching the C API fingerprint.h."""

    SUCCESS = 0
    BUFFER_FULL = 1
    INVALID_FEATURE = 2
    INVALID_TYPE = 3
    NOT_INITIALIZED = 4
