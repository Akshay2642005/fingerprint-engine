#!/usr/bin/env python3
"""
Fingerprint Engine — Python SDK Demo.

Demonstrates collecting fingerprint signals, computing a SHA-256 digest,
and comparing two fingerprints for similarity.

Prerequisites:
    zig build native  (build the native library from project root)
"""

import sys
import os

# Add package to path if running from examples/
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

from fingerprint_sdk import FingerprintEngine, FeatureID  # type: ignore[import]


def main():
    print("Fingerprint Engine — Python Demo")
    print("=" * 40)

    # ── Fingerprint 1: Windows/Chrome simulation ──
    print("\n◌ Computing fingerprint 1 (Windows/Chrome)...")
    engine1 = FingerprintEngine()
    engine1.add_boolean(FeatureID.COOKIE_ENABLED, True)
    engine1.add_string(
        FeatureID.USER_AGENT,
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    )
    engine1.add_string(FeatureID.LANGUAGE, "en-US")
    engine1.add_string(FeatureID.PLATFORM, "Win32")
    engine1.add_integer(FeatureID.HARDWARE_CONCURRENCY, 8)
    engine1.add_integer(FeatureID.DEVICE_MEMORY, 8)
    engine1.add_integer(FeatureID.SCREEN_WIDTH, 1920)
    engine1.add_integer(FeatureID.SCREEN_HEIGHT, 1080)
    engine1.add_integer(FeatureID.SCREEN_COLOR_DEPTH, 24)
    engine1.add_float(FeatureID.SCREEN_DPI, 1.0)
    engine1.add_string(FeatureID.TIMEZONE, "America/New_York")

    digest1 = engine1.compute()
    print(f"  Digest: {digest1.hex()}")

    # ── Fingerprint 2: macOS/Firefox simulation ──
    print("\n◌ Computing fingerprint 2 (macOS/Firefox)...")
    engine2 = FingerprintEngine()
    engine2.add_boolean(FeatureID.COOKIE_ENABLED, True)
    engine2.add_string(
        FeatureID.USER_AGENT,
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:121.0) "
        "Gecko/20100101 Firefox/121.0",
    )
    engine2.add_string(FeatureID.LANGUAGE, "en-US")
    engine2.add_string(FeatureID.PLATFORM, "MacIntel")
    engine2.add_integer(FeatureID.HARDWARE_CONCURRENCY, 10)
    engine2.add_integer(FeatureID.DEVICE_MEMORY, 16)
    engine2.add_integer(FeatureID.SCREEN_WIDTH, 2560)
    engine2.add_integer(FeatureID.SCREEN_HEIGHT, 1600)
    engine2.add_integer(FeatureID.SCREEN_COLOR_DEPTH, 30)
    engine2.add_float(FeatureID.SCREEN_DPI, 2.0)
    engine2.add_string(FeatureID.TIMEZONE, "America/Los_Angeles")

    digest2 = engine2.compute()
    print(f"  Digest: {digest2.hex()}")

    # ── Comparison ──
    print("\n◌ Comparison:")
    print(f"  Fingerprint 1: {digest1.hex()[:16]}...")
    print(f"  Fingerprint 2: {digest2.hex()[:16]}...")
    match = digest1 == digest2
    print(f"  Match: {'✅ YES' if match else '❌ NO'}")

    if not match:
        diff_count = sum(1 for a, b in zip(digest1, digest2, strict=True) if a != b)
        print(f"  Differing bytes: {diff_count}/32")

    print("\n✓ Demo complete")


if __name__ == "__main__":
    main()
