import { describe, expect, it } from "vitest";
import {
  DEFAULT_ZONES, formatOffset, formatTime, normalizePreferences, removeZone,
} from "./clock";

describe("world clock preferences", () => {
  it("keeps the selected IANA zones and removes duplicates and invalid identifiers", () => {
    const value = normalizePreferences({
      identifiers: ["Asia/Shanghai", "Asia/Shanghai", "Not/A_Zone", "Europe/London"],
      primary: "Europe/London",
      showSeconds: true,
    });
    expect(value.identifiers).toEqual(["Asia/Shanghai", "Europe/London"]);
    expect(value.primary).toBe("Europe/London");
    expect(value.showSeconds).toBe(true);
  });

  it("falls back to defaults when a saved selection is invalid", () => {
    const value = normalizePreferences({ identifiers: ["Invalid/Zone"], primary: "Invalid/Zone" });
    expect(value.identifiers).toEqual(DEFAULT_ZONES);
    expect(value.primary).toBe("Asia/Shanghai");
  });

  it("repins the first remaining zone and never removes the final zone", () => {
    const initial = normalizePreferences({ identifiers: ["Asia/Shanghai", "Asia/Tokyo"], primary: "Asia/Shanghai" });
    const remaining = removeZone(initial, "Asia/Shanghai");
    expect(remaining.primary).toBe("Asia/Tokyo");
    expect(removeZone(remaining, "Asia/Tokyo")).toBe(remaining);
  });
});

describe("daylight saving time", () => {
  it("skips the missing hour in New York in March", () => {
    const before = new Date("2026-03-08T06:59:00Z");
    const after = new Date("2026-03-08T07:01:00Z");
    expect(formatTime(before, "America/New_York", "en-US", false)).toBe("01:59");
    expect(formatTime(after, "America/New_York", "en-US", false)).toBe("03:01");
    expect(formatOffset(before, "America/New_York")).toBe("UTC-5");
    expect(formatOffset(after, "America/New_York")).toBe("UTC-4");
  });
});
