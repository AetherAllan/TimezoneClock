export type Language = "system" | "zh-Hans" | "zh-Hant" | "en";

export interface ClockPreferences {
  identifiers: string[];
  primary: string;
  language: Language;
  showDate: boolean;
  showSeconds: boolean;
  showGlobe: boolean;
}

export const STORAGE_KEY = "timezoneclock.windows.v1";
export const DEFAULT_ZONES = [
  "Asia/Shanghai",
  "America/Los_Angeles",
  "America/New_York",
  "Europe/London",
  "Asia/Tokyo",
];

export const DEFAULT_PREFERENCES: ClockPreferences = {
  identifiers: DEFAULT_ZONES,
  primary: DEFAULT_ZONES[0],
  language: "zh-Hans",
  showDate: false,
  showSeconds: false,
  showGlobe: false,
};

export function isValidZone(identifier: string): boolean {
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: identifier });
    return true;
  } catch {
    return false;
  }
}

export function normalizePreferences(raw: unknown): ClockPreferences {
  if (!raw || typeof raw !== "object") return { ...DEFAULT_PREFERENCES, identifiers: [...DEFAULT_ZONES] };
  const value = raw as Record<string, unknown>;
  const seen = new Set<string>();
  const identifiers = Array.isArray(value.identifiers)
    ? value.identifiers.filter((id): id is string => {
        if (typeof id !== "string" || !isValidZone(id) || seen.has(id)) return false;
        seen.add(id);
        return true;
      })
    : [];
  const list = identifiers.length ? identifiers : [...DEFAULT_ZONES];
  const primary = typeof value.primary === "string" && list.includes(value.primary)
    ? value.primary : list[0];
  const language: Language =
    value.language === "system" || value.language === "zh-Hans" ||
    value.language === "zh-Hant" || value.language === "en"
      ? value.language : DEFAULT_PREFERENCES.language;
  return {
    identifiers: list,
    primary,
    language,
    showDate: value.showDate === true,
    showSeconds: value.showSeconds === true,
    showGlobe: value.showGlobe === true,
  };
}

export function removeZone(preferences: ClockPreferences, zone: string): ClockPreferences {
  if (preferences.identifiers.length <= 1) return preferences;
  const identifiers = preferences.identifiers.filter((item) => item !== zone);
  if (identifiers.length === preferences.identifiers.length) return preferences;
  return {
    ...preferences,
    identifiers,
    primary: preferences.primary === zone ? identifiers[0] : preferences.primary,
  };
}

export function localeFor(language: Language): string {
  return language === "system" ? navigator.language || "en" : language;
}

export function formatTime(date: Date, identifier: string, locale: string, seconds: boolean): string {
  return new Intl.DateTimeFormat(locale, {
    timeZone: identifier,
    hour: "2-digit",
    minute: "2-digit",
    ...(seconds ? { second: "2-digit" } : {}),
    hourCycle: "h23",
  }).format(date);
}

export function formatDay(date: Date, identifier: string, locale: string): string {
  return new Intl.DateTimeFormat(locale, {
    timeZone: identifier,
    month: "short",
    day: "numeric",
    weekday: "short",
  }).format(date);
}

export function formatOffset(date: Date, identifier: string): string {
  const part = new Intl.DateTimeFormat("en-US", {
    timeZone: identifier,
    timeZoneName: "shortOffset",
  }).formatToParts(date).find((item) => item.type === "timeZoneName");
  return part?.value.replace("GMT", "UTC") ?? "UTC";
}

export function allZones(): string[] {
  // Keep selected aliases such as Asia/Shanghai even when supportedValuesOf omits them.
  const listed = typeof Intl.supportedValuesOf === "function"
    ? Intl.supportedValuesOf("timeZone") : [];
  return [...new Set([...DEFAULT_ZONES, ...listed])];
}
