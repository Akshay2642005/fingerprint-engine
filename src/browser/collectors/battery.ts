/**
 * Battery status collector.
 * Uses the Battery Manager API to collect battery state.
 * Note: Requires user gesture in some browsers; may return null.
 */

export interface BatteryInfo {
  level: number;
  charging: boolean;
  chargingTime: number;
}

/**
 * Collect battery status. Returns null if API unavailable.
 */
export async function collectBattery(): Promise<BatteryInfo | null> {
  try {
    const nav = navigator as Navigator & {
      getBattery?: () => Promise<{
        level: number;
        charging: boolean;
        chargingTime: number;
      }>;
    };
    if (!nav.getBattery) return null;
    const battery = await nav.getBattery();
    return {
      level: Math.round(battery.level * 100),
      charging: battery.charging,
      chargingTime: battery.chargingTime === Infinity ? -1 : Math.round(battery.chargingTime),
    };
  } catch {
    return null;
  }
}
