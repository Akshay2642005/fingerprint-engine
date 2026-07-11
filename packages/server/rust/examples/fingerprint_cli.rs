/// Fingerprint Engine — Rust CLI Example.
///
/// Collects a set of representative browser signals and prints the
/// SHA-256 fingerprint digest in hex format.
///
/// Usage:
///   cargo run --example fingerprint_cli

use fingerprint_sdk::{FingerprintEngine, FeatureID};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("Fingerprint Engine — Rust CLI");
    println!("==============================");

    let mut engine = FingerprintEngine::new()?;

    // Simulate browser signals
    engine.add_boolean(FeatureID::CookieEnabled, true)?;
    engine.add_string(
        FeatureID::UserAgent,
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) \
         AppleWebKit/537.36 (KHTML, like Gecko) \
         Chrome/120.0.0.0 Safari/537.36",
    )?;
    engine.add_string(FeatureID::Language, "en-US")?;
    engine.add_string(FeatureID::Platform, "Win32")?;
    engine.add_integer(FeatureID::HardwareConcurrency, 8)?;
    engine.add_integer(FeatureID::DeviceMemory, 8)?;
    engine.add_integer(FeatureID::ScreenWidth, 1920)?;
    engine.add_integer(FeatureID::ScreenHeight, 1080)?;
    engine.add_string(FeatureID::Timezone, "America/New_York")?;

    let digest = engine.compute()?;
    let hex: String = digest.iter().map(|b| format!("{:02x}", b)).collect();

    println!("Signals collected: 9");
    println!("Fingerprint digest: {}", hex);
    println!();
    println!("✓ Done");

    Ok(())
}
