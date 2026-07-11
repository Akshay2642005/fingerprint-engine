//! Fingerprint Engine — Rust SDK.
//!
//! Safe Rust bindings to the Zig-compiled native fingerprint library.
//! Supports fingerprint collection, SHA-256 digest computation, and
//! similarity scoring for browser fingerprinting applications.
//!
//! # Quick Start
//!
//! ```rust,no_run
//! use fingerprint_sdk::{FingerprintEngine, FeatureID};
//!
//! let mut engine = FingerprintEngine::new().unwrap();
//! engine.add_boolean(FeatureID::CookieEnabled, true).unwrap();
//! engine.add_string(FeatureID::UserAgent, "Mozilla/5.0 ...").unwrap();
//! let digest = engine.compute().unwrap();
//! println!("Digest: {}", hex::encode(digest));
//! ```

mod ffi {
    #![allow(non_camel_case_types, dead_code)]

    use libc::{c_int, c_uchar, c_void};

    /// Opaque handle to the Zig engine.
    pub type FingerprintEngineOpaque = c_void;

    extern "C" {
        pub fn fingerprint_engine_create() -> *mut FingerprintEngineOpaque;
        pub fn fingerprint_engine_destroy(engine: *mut FingerprintEngineOpaque);
        pub fn fingerprint_engine_add_feature(
            engine: *mut FingerprintEngineOpaque,
            feature_id: c_int,
            value_type: c_int,
            value_data: *const c_uchar,
            value_len: c_int,
        ) -> c_int;
        pub fn fingerprint_engine_compute(
            engine: *mut FingerprintEngineOpaque,
            out_digest: *mut c_uchar,
            out_len: *mut c_int,
        ) -> c_int;
    }
}

use std::ptr;

/// Error codes matching the C API `fingerprint.h`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(i32)]
pub enum ErrorCode {
    Success = 0,
    BufferFull = 1,
    InvalidFeature = 2,
    InvalidType = 3,
    NotInitialized = 4,
}

impl ErrorCode {
    fn from_i32(code: i32) -> Self {
        match code {
            0 => ErrorCode::Success,
            1 => ErrorCode::BufferFull,
            2 => ErrorCode::InvalidFeature,
            3 => ErrorCode::InvalidType,
            4 => ErrorCode::NotInitialized,
            _ => ErrorCode::InvalidFeature,
        }
    }
}

/// Errors returned by the fingerprint engine.
#[derive(Debug)]
pub enum FingerprintError {
    /// The native library returned a non-success error code.
    Native(ErrorCode),
    /// Failed to create the engine (allocation failure).
    CreateFailed,
    /// Output buffer too small.
    BufferTooSmall,
}

impl std::fmt::Display for FingerprintError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            FingerprintError::Native(code) => write!(f, "native error: {:?}", code),
            FingerprintError::CreateFailed => write!(f, "failed to create engine"),
            FingerprintError::BufferTooSmall => write!(f, "buffer too small"),
        }
    }
}

impl std::error::Error for FingerprintError {}

/// Feature ID constants matching `src/core/features/model.zig`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[repr(i32)]
pub enum FeatureID {
    // Navigator
    CookieEnabled = 0,
    UserAgent = 1,
    Language = 2,
    Languages = 3,
    Platform = 4,
    Vendor = 5,
    VendorSub = 6,
    Product = 7,
    ProductSub = 8,
    AppName = 9,
    AppVersion = 10,
    DoNotTrack = 11,
    HardwareConcurrency = 12,
    MaxTouchPoints = 13,
    DeviceMemory = 14,
    Timezone = 15,
    TimezoneOffset = 16,
    // Screen
    ScreenWidth = 17,
    ScreenHeight = 18,
    ScreenAvailWidth = 19,
    ScreenAvailHeight = 20,
    ScreenColorDepth = 21,
    ScreenPixelDepth = 22,
    ScreenDpi = 23,
    // Window
    WindowInnerWidth = 24,
    WindowInnerHeight = 25,
    WindowOuterWidth = 26,
    WindowOuterHeight = 27,
    // Fonts & Media
    Fonts = 28,
    MediaDevices = 29,
    // Canvas & WebGL
    Canvas = 30,
    WebglVendor = 31,
    WebglRenderer = 32,
    WebglVersion = 33,
    // Audio & Network
    Audio = 34,
    ConnectionType = 35,
    ConnectionDownlink = 36,
}

/// The 32-byte SHA-256 digest type.
pub type FingerprintDigest = [u8; 32];

/// Type-safe wrapper around the native fingerprint engine.
pub struct FingerprintEngine {
    handle: *mut ffi::FingerprintEngineOpaque,
}

// Safety: the engine handle is thread-compatible (not thread-safe).
unsafe impl Send for FingerprintEngine {}

impl FingerprintEngine {
    /// Create a new fingerprint engine instance.
    pub fn new() -> Result<Self, FingerprintError> {
        let handle = unsafe { ffi::fingerprint_engine_create() };
        if handle.is_null() {
            return Err(FingerprintError::CreateFailed);
        }
        Ok(FingerprintEngine { handle })
    }

    /// Destroy the engine and free associated memory.
    fn destroy(&mut self) {
        if !self.handle.is_null() {
            unsafe { ffi::fingerprint_engine_destroy(self.handle) };
            self.handle = ptr::null_mut();
        }
    }

    /// Add a feature with raw bytes.
    fn add_raw(
        &self,
        feature_id: i32,
        value_type: i32,
        data: &[u8],
    ) -> Result<(), FingerprintError> {
        let rc = unsafe {
            ffi::fingerprint_engine_add_feature(
                self.handle,
                feature_id,
                value_type,
                data.as_ptr(),
                data.len() as i32,
            )
        };
        if rc == 0 {
            Ok(())
        } else {
            Err(FingerprintError::Native(ErrorCode::from_i32(rc)))
        }
    }

    // ── Typed add methods ──

    pub fn add_boolean(&self, id: FeatureID, value: bool) -> Result<(), FingerprintError> {
        self.add_raw(id as i32, 0, &[value as u8])
    }

    pub fn add_integer(&self, id: FeatureID, value: i64) -> Result<(), FingerprintError> {
        self.add_raw(id as i32, 1, &value.to_le_bytes())
    }

    pub fn add_float(&self, id: FeatureID, value: f64) -> Result<(), FingerprintError> {
        self.add_raw(id as i32, 2, &value.to_le_bytes())
    }

    pub fn add_string(&self, id: FeatureID, value: &str) -> Result<(), FingerprintError> {
        self.add_raw(id as i32, 3, value.as_bytes())
    }

    pub fn add_bytes(&self, id: FeatureID, value: &[u8]) -> Result<(), FingerprintError> {
        self.add_raw(id as i32, 4, value)
    }

    /// Compute the SHA-256 fingerprint digest.
    ///
    /// Returns a 32-byte digest on success.
    pub fn compute(&self) -> Result<FingerprintDigest, FingerprintError> {
        let mut digest: FingerprintDigest = [0u8; 32];
        let mut out_len: i32 = digest.len() as i32;

        let rc = unsafe {
            ffi::fingerprint_engine_compute(
                self.handle,
                digest.as_mut_ptr(),
                &mut out_len,
            )
        };
        if rc != 0 {
            return Err(FingerprintError::Native(ErrorCode::from_i32(rc)));
        }
        if out_len as usize != digest.len() {
            return Err(FingerprintError::BufferTooSmall);
        }
        Ok(digest)
    }
}

impl Drop for FingerprintEngine {
    fn drop(&mut self) {
        self.destroy();
    }
}

// ── Tests ──

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_create_and_destroy() {
        let engine = FingerprintEngine::new();
        assert!(engine.is_ok());
    }

    #[test]
    fn test_add_boolean_feature() {
        let engine = FingerprintEngine::new().unwrap();
        assert!(engine.add_boolean(FeatureID::CookieEnabled, true).is_ok());
    }

    #[test]
    fn test_compute_produces_32_bytes() {
        let engine = FingerprintEngine::new().unwrap();
        engine.add_boolean(FeatureID::CookieEnabled, true).unwrap();
        engine.add_string(FeatureID::UserAgent, "test").unwrap();
        let digest = engine.compute().unwrap();
        assert_eq!(digest.len(), 32);
    }

    #[test]
    fn test_deterministic_digest() {
        let engine1 = FingerprintEngine::new().unwrap();
        engine1.add_boolean(FeatureID::CookieEnabled, true).unwrap();
        engine1.add_integer(FeatureID::HardwareConcurrency, 8).unwrap();
        let d1 = engine1.compute().unwrap();

        let engine2 = FingerprintEngine::new().unwrap();
        engine2.add_boolean(FeatureID::CookieEnabled, true).unwrap();
        engine2.add_integer(FeatureID::HardwareConcurrency, 8).unwrap();
        let d2 = engine2.compute().unwrap();

        assert_eq!(d1, d2, "digest should be deterministic");
    }

    #[test]
    fn test_different_features_different_digests() {
        let engine1 = FingerprintEngine::new().unwrap();
        engine1.add_boolean(FeatureID::CookieEnabled, true).unwrap();
        let d1 = engine1.compute().unwrap();

        let engine2 = FingerprintEngine::new().unwrap();
        engine2.add_boolean(FeatureID::CookieEnabled, false).unwrap();
        let d2 = engine2.compute().unwrap();

        assert_ne!(d1, d2, "different values should produce different digests");
    }
}
