"""
Fingerprint Engine — Python SDK.

Provides ctypes-based bindings to the native fingerprint static library.
Supports fingerprint collection, SHA-256 digest computation, and similarity
scoring for browser fingerprinting applications.

Usage:
    from fingerprint_sdk import FingerprintEngine, FeatureID

    engine = FingerprintEngine()
    engine.add_boolean(FeatureID.COOKIE_ENABLED, True)
    engine.add_string(FeatureID.USER_AGENT, "Mozilla/5.0 ...")
    digest = engine.compute()
    print(digest.hex())
"""

from fingerprint_sdk.engine import FingerprintEngine
from fingerprint_sdk.types import FeatureID, FeatureType, ErrorCode

__all__ = ["FingerprintEngine", "FeatureID", "FeatureType", "ErrorCode"]
