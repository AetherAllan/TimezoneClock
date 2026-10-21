import type { Language } from "./clock";

type Translation = {
  worldClock: string;
  addZone: string;
  settings: string;
  search: string;
  noResults: string;
  selected: string;
  pin: string;
  remove: string;
  back: string;
  close: string;
  display: string;
  showDate: string;
  showSeconds: string;
  startAtLogin: string;
  globe: string;
  globeHint: string;
  language: string;
  trayHint: string;
  traySystemHint: string;
  statusError: string;
};

const translations: Record<Exclude<Language, "system">, Translation> = {
  "zh-Hans": {
    worldClock: "世界时钟", addZone: "添加时区", settings: "设置", search: "搜索城市或时区",
    noResults: "没有匹配的时区", selected: "已添加", pin: "设为托盘时间", remove: "移除时区",
    back: "返回", close: "关闭", display: "显示", showDate: "显示日期", showSeconds: "显示秒数",
    startAtLogin: "登录时启动", globe: "3D 地球", globeHint: "仅在弹窗显示时渲染",
    language: "语言", trayHint: "托盘显示所选时区的小时与分钟，上下排列。",
    traySystemHint: "托盘图标尺寸由 Windows 决定；在任务栏设置中把本应用设为常显。",
    statusError: "操作失败",
  },
  "zh-Hant": {
    worldClock: "世界時鐘", addZone: "新增時區", settings: "設定", search: "搜尋城市或時區",
    noResults: "沒有符合的時區", selected: "已新增", pin: "設為通知區域時間", remove: "移除時區",
    back: "返回", close: "關閉", display: "顯示", showDate: "顯示日期", showSeconds: "顯示秒數",
    startAtLogin: "登入時啟動", globe: "3D 地球", globeHint: "僅於彈出視窗顯示時渲染",
    language: "語言", trayHint: "通知區域顯示所選時區的小時與分鐘，上下排列。",
    traySystemHint: "圖示大小由 Windows 決定；可在工作列設定中將本應用設為常顯。",
    statusError: "操作失敗",
  },
  en: {
    worldClock: "World Clock", addZone: "Add Time Zone", settings: "Settings", search: "Search city or time zone",
    noResults: "No matching time zones", selected: "Added", pin: "Show in tray", remove: "Remove time zone",
    back: "Back", close: "Close", display: "Display", showDate: "Show date", showSeconds: "Show seconds",
    startAtLogin: "Launch at login", globe: "3D globe", globeHint: "Rendered only while the popup is open",
    language: "Language", trayHint: "The tray icon shows hours over minutes in the selected time zone.",
    traySystemHint: "Windows controls tray icon size. Set this app to always show in Taskbar settings.",
    statusError: "Operation failed",
  },
};

export function resolvedLanguage(language: Language): Exclude<Language, "system"> {
  if (language !== "system") return language;
  const value = navigator.language.toLowerCase();
  if (value.startsWith("zh")) {
    return /tw|hk|hant/.test(value) ? "zh-Hant" : "zh-Hans";
  }
  return "en";
}

export function t(language: Language): Translation {
  return translations[resolvedLanguage(language)];
}

const cities: Record<string, { "zh-Hans": string; "zh-Hant": string; en: string }> = {
  "Asia/Shanghai": { "zh-Hans": "北京", "zh-Hant": "北京", en: "Beijing" },
  "America/Los_Angeles": { "zh-Hans": "洛杉矶", "zh-Hant": "洛杉磯", en: "Los Angeles" },
  "America/New_York": { "zh-Hans": "纽约", "zh-Hant": "紐約", en: "New York" },
  "Europe/London": { "zh-Hans": "伦敦", "zh-Hant": "倫敦", en: "London" },
  "Asia/Tokyo": { "zh-Hans": "东京", "zh-Hant": "東京", en: "Tokyo" },
};

export function cityName(zone: string, language: Language): string {
  return cities[zone]?.[resolvedLanguage(language)]
    ?? zone.split("/").at(-1)?.replaceAll("_", " ")
    ?? zone;
}

export function matchesZone(zone: string, query: string, language: Language): boolean {
  const search = query.trim().toLocaleLowerCase();
  if (!search) return true;
  return [zone, zone.replaceAll("_", " "), cityName(zone, language),
    cities[zone]?.["zh-Hans"], cities[zone]?.["zh-Hant"], cities[zone]?.en]
    .some((value) => value?.toLocaleLowerCase().includes(search));
}
