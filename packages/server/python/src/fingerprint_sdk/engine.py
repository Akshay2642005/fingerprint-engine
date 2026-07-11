"""
Python bindings to the Fingerprint Engine native library.

Uses ctypes to load the compiled libfingerprint library and expose
its C-compatible API with Pythonic type hints and error handling.
"""

import ctypes
import ctypes.util
import platform
import struct
from pathlib import Path

from fingerprint_sdk.types import FeatureType, ErrorCode

# ── Load native library ──

def _find_lib_path() -> Path | None:
    """Search for the compiled fingerprint native library."""
    # Common locations relative to this package
    root = Path(__file__).resolve().parent.parent.parent.parent.parent.parent
    zig_out = root / "zig-out" / "lib"

    if platform.system() == "Windows":
        candidates = [
            zig_out / "fingerprint.lib",
            root / "zig-out" / "lib" / "fingerprint.dll",
        ]
    elif platform.system() == "Darwin":
        candidates = [zig_out / "libfingerprint.a"]
    else:  # Linux
        candidates = [zig_out / "libfingerprint.a"]

    for path in candidates:
        if path.exists():
            return path

    # Fallback: system library search
    found = ctypes.util.find_library("fingerprint")
    if found:
        return Path(found)

    return None


def _load_library():
    """Load the fingerprint native library via ctypes."""
    lib_path = _find_lib_path()
    if lib_path is None:
        raise RuntimeError(
            "fingerprint native library not found. "
            "Run 'zig build native' from the project root."
        )

    if platform.system() == "Windows":
        return ctypes.CDLL(str(lib_path))
    else:
        return ctypes.CDLL(str(lib_path))


# Load at module level
_lib = _load_library()

# ── Configure function signatures ──

_lib.fingerprint_engine_create.restype = ctypes.c_void_p
_lib.fingerprint_engine_create.argtypes = []

_lib.fingerprint_engine_destroy.restype = None
_lib.fingerprint_engine_destroy.argtypes = [ctypes.c_void_p]

_lib.fingerprint_engine_add_feature.restype = ctypes.c_int
_lib.fingerprint_engine_add_feature.argtypes = [
    ctypes.c_void_p,  # engine handle
    ctypes.c_int,  # feature_id
    ctypes.c_int,  # value_type
    ctypes.POINTER(ctypes.c_ubyte),  # value_data
    ctypes.c_int,  # value_len
]

_lib.fingerprint_engine_compute.restype = ctypes.c_int
_lib.fingerprint_engine_compute.argtypes = [
    ctypes.c_void_p,  # engine handle
    ctypes.POINTER(ctypes.c_ubyte),  # out_digest
    ctypes.POINTER(ctypes.c_int),  # out_len
]

_lib.fingerprint_engine_normalize.restype = ctypes.c_int
_lib.fingerprint_engine_normalize.argtypes = [ctypes.c_void_p]

_lib.fingerprint_engine_risk.restype = ctypes.c_int
_lib.fingerprint_engine_risk.argtypes = [ctypes.c_void_p]

_lib.fingerprint_engine_entropy.restype = ctypes.c_int
_lib.fingerprint_engine_entropy.argtypes = [ctypes.c_void_p]


class FingerprintError(Exception):
    """Raised when a fingerprint engine operation fails."""

    def __init__(self, code: int, message: str = ""):
        self.code = code
        self.message = message or f"Error code {code}"
        super().__init__(self.message)


class FingerprintEngine:
    """Pythonic wrapper around the native FingerprintEngine handle.

    Manages the lifecycle of a fingerprint engine instance and provides
    type-safe methods for collecting features and computing digests.

    Usage:
        engine = FingerprintEngine()
        engine.add_boolean(FeatureID.COOKIE_ENABLED, True)
        engine.add_string(FeatureID.USER_AGENT, "Mozilla/5.0 ...")
        digest = engine.compute()
        print(digest.hex())
    """

    def __init__(self):
        self._handle = _lib.fingerprint_engine_create()
        if not self._handle:
            raise RuntimeError("Failed to create fingerprint engine")

    def __del__(self):
        if hasattr(self, "_handle") and self._handle:
            _lib.fingerprint_engine_destroy(self._handle)
            self._handle = None

    def _add_raw(self, feature_id: int, value_type: int, data: bytes) -> None:
        """Add a feature with raw bytes."""
        arr = (ctypes.c_ubyte * len(data)).from_buffer_copy(data)
        rc = _lib.fingerprint_engine_add_feature(
            self._handle,
            feature_id,
            value_type,
            arr,
            len(data),
        )
        if rc != ErrorCode.SUCCESS:
            raise FingerprintError(rc, f"add_feature failed (id={feature_id})")

    # ── Typed add methods ──

    def add_boolean(self, feature_id: int, value: bool) -> None:
        self._add_raw(feature_id, FeatureType.BOOLEAN, bytes([1 if value else 0]))

    def add_integer(self, feature_id: int, value: int) -> None:
        self._add_raw(feature_id, FeatureType.INTEGER, struct.pack("<q", value))

    def add_float(self, feature_id: int, value: float) -> None:
        self._add_raw(feature_id, FeatureType.FLOAT, struct.pack("<d", value))

    def add_string(self, feature_id: int, value: str) -> None:
        self._add_raw(feature_id, FeatureType.STRING, value.encode("utf-8"))

    def add_bytes(self, feature_id: int, value: bytes) -> None:
        self._add_raw(feature_id, FeatureType.BYTES, value)

    def add_string_array(self, feature_id: int, value: list[str]) -> None:
        encoded = [s.encode("utf-8") for s in value]
        self._add_raw(
            feature_id, FeatureType.STRING_ARRAY, b"\x00".join(encoded)
        )

    def add_integer_array(self, feature_id: int, value: list[int]) -> None:
        data = struct.pack(f"<{len(value)}q", *value)
        self._add_raw(feature_id, FeatureType.INTEGER_ARRAY, data)

    def add_float_array(self, feature_id: int, value: list[float]) -> None:
        data = struct.pack(f"<{len(value)}d", *value)
        self._add_raw(feature_id, FeatureType.FLOAT_ARRAY, data)

    # ── Computation ──

    def compute(self) -> bytes:
        """Compute the SHA-256 fingerprint digest.

        Returns 32 bytes (the SHA-256 digest).
        """
        digest = (ctypes.c_ubyte * 32)()
        out_len = ctypes.c_int(32)

        rc = _lib.fingerprint_engine_compute(
            self._handle, digest, ctypes.byref(out_len)
        )
        if rc != ErrorCode.SUCCESS:
            raise FingerprintError(rc, "compute failed")

        return bytes(digest[: out_len.value])

    def compute_hex(self) -> str:
        """Compute the fingerprint digest and return as hex string."""
        return self.compute().hex()

    # ── Processing ──

    def normalize(self) -> int:
        """Normalize the fingerprint, checking for type and bounds issues.

        Returns:
            Number of warnings (0 = clean).
        """
        rc = _lib.fingerprint_engine_normalize(self._handle)
        if rc < 0:
            raise FingerprintError(rc, "normalize failed")
        return rc

    def risk(self) -> int:
        """Compute risk assessment score.

        Returns:
            Risk score (0-100, where 100 = highest risk).
        """
        rc = _lib.fingerprint_engine_risk(self._handle)
        if rc < 0:
            raise FingerprintError(rc, "risk computation failed")
        return rc

    def entropy(self) -> int:
        """Compute fingerprint entropy.

        Returns:
            Entropy score (0-800, where 800 = 8.0 bits/byte * 100).
        """
        rc = _lib.fingerprint_engine_entropy(self._handle)
        if rc < 0:
            raise FingerprintError(rc, "entropy computation failed")
        return rc
