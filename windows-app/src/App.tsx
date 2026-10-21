import { lazy, Suspense, useEffect, useMemo, useState } from "react";
import { invoke, isTauri } from "@tauri-apps/api/core";
import { disable, enable, isEnabled } from "@tauri-apps/plugin-autostart";
import { ArrowLeft, Check, Globe2, Pin, Plus, Search, Settings2, Trash2, X } from "lucide-react";
import { HaloButton } from "@/components/ui/halo-button";
import {
  allZones, DEFAULT_ZONES, formatDay, formatOffset, formatTime, localeFor,
  normalizePreferences, removeZone, STORAGE_KEY, type ClockPreferences,
} from "./clock";
import { cityName, matchesZone, t } from "./i18n";
import "./App.css";

const Globe = lazy(() => import("./Globe"));
type View = "clock" | "add" | "settings";

function loadPreferences(): ClockPreferences {
  try {
    return normalizePreferences(JSON.parse(localStorage.getItem(STORAGE_KEY) ?? "null"));
  } catch {
    return normalizePreferences(null);
  }
}

function App() {
  const [preferences, setPreferences] = useState(loadPreferences);
  const [now, setNow] = useState(() => new Date());
  const [view, setView] = useState<View>("clock");
  const [query, setQuery] = useState("");
  const [autostart, setAutostart] = useState(false);
  const [error, setError] = useState("");
  const [focused, setFocused] = useState(() => document.hasFocus());
  const labels = t(preferences.language);
  const locale = localeFor(preferences.language);
  const zones = useMemo(allZones, []);
  const matches = useMemo(
    () => zones.filter((zone) => matchesZone(zone, query, preferences.language)),
    [zones, query, preferences.language],
  );

  useEffect(() => {
    const tick = () => setNow(new Date());
    const timer = window.setInterval(tick, 1000);
    window.addEventListener("focus", tick);
    document.addEventListener("visibilitychange", tick);
    return () => {
      window.clearInterval(timer);
      window.removeEventListener("focus", tick);
      document.removeEventListener("visibilitychange", tick);
    };
  }, []);

  useEffect(() => {
    const activate = () => setFocused(true);
    const deactivate = () => setFocused(false);
    window.addEventListener("focus", activate);
    window.addEventListener("blur", deactivate);
    return () => {
      window.removeEventListener("focus", activate);
      window.removeEventListener("blur", deactivate);
    };
  }, []);

  useEffect(() => {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(preferences));
    } catch {
      // The app still works if WebView storage has been disabled.
    }
  }, [preferences]);

  useEffect(() => {
    if (!isTauri()) return;
    void invoke("set_primary_zone", { zone: preferences.primary }).catch((reason: unknown) => {
      setError(String(reason));
      if (preferences.primary !== DEFAULT_ZONES[0]) {
        setPreferences((current) => ({ ...current, primary: DEFAULT_ZONES[0] }));
      }
    });
  }, [preferences.primary]);

  useEffect(() => {
    if (!isTauri()) return;
    void isEnabled().then(setAutostart).catch((reason: unknown) => setError(String(reason)));
  }, []);

  async function pin(zone: string) {
    if (zone === preferences.primary) return;
    setError("");
    try {
      if (isTauri()) await invoke("set_primary_zone", { zone });
      setPreferences((current) => ({ ...current, primary: zone }));
    } catch (reason) {
      setError(`${labels.statusError}: ${String(reason)}`);
    }
  }

  function add(zone: string) {
    setPreferences((current) => current.identifiers.includes(zone)
      ? current : { ...current, identifiers: [...current.identifiers, zone] });
    setQuery("");
    setView("clock");
  }

  async function toggleAutostart() {
    if (!isTauri()) return;
    setError("");
    try {
      if (autostart) await disable();
      else await enable();
      setAutostart(await isEnabled());
    } catch (reason) {
      setError(`${labels.statusError}: ${String(reason)}`);
    }
  }

  function back() {
    setError("");
    setQuery("");
    setView("clock");
  }

  const pinnedName = cityName(preferences.primary, preferences.language);
  return (
    <main className="clock-shell">
      <header className="window-header">
        <div className="window-heading">
          {view === "clock" ? <Globe2 size={18} aria-hidden="true" /> : (
            <button className="icon-button" onClick={back} aria-label={labels.back} title={labels.back}>
              <ArrowLeft size={18} />
            </button>
          )}
          <div>
            <div className="window-title">{view === "clock" ? labels.worldClock : view === "add" ? labels.addZone : labels.settings}</div>
            <div className="window-subtitle">TimezoneClock · Windows</div>
          </div>
        </div>
        <div className="header-actions">
          {view === "clock" && <>
            <button className="icon-button" onClick={() => setView("add")} title={labels.addZone} aria-label={labels.addZone}><Plus size={18} /></button>
            <button className="icon-button" onClick={() => setView("settings")} title={labels.settings} aria-label={labels.settings}><Settings2 size={18} /></button>
          </>}
          <button className="icon-button" onClick={() => { if (isTauri()) void invoke("hide_popup"); }} title={labels.close} aria-label={labels.close}><X size={18} /></button>
        </div>
      </header>

      {view === "clock" && <>
        <section className="hero" aria-label={`${pinnedName} ${formatTime(now, preferences.primary, locale, preferences.showSeconds)}`}>
          <div className="hero-zone"><Pin size={13} fill="currentColor" /> {pinnedName} <span>{formatOffset(now, preferences.primary)}</span></div>
          <div className="hero-time">{formatTime(now, preferences.primary, locale, preferences.showSeconds)}</div>
          {preferences.showDate && <div className="hero-date">{formatDay(now, preferences.primary, locale)}</div>}
        </section>
        {preferences.showGlobe && focused && (
          <Suspense fallback={<div className="globe-preview" />}><Globe /></Suspense>
        )}
        <section className="zone-list" aria-label={labels.worldClock}>
          {preferences.identifiers.map((zone) => {
            const selected = zone === preferences.primary;
            return (
              <div className={`zone-row ${selected ? "zone-row-selected" : ""}`} key={zone}>
                <button className="zone-main" onClick={() => void pin(zone)} aria-label={`${cityName(zone, preferences.language)} · ${labels.pin}`}>
                  <span className="zone-name">{cityName(zone, preferences.language)} {selected && <Pin size={12} fill="currentColor" aria-hidden="true" />}</span>
                  <span className="zone-detail">{formatDay(now, zone, locale)} · {formatOffset(now, zone)}</span>
                </button>
                <span className="zone-time">{formatTime(now, zone, locale, preferences.showSeconds)}</span>
                <button className="remove-button" title={labels.remove} aria-label={`${labels.remove} ${cityName(zone, preferences.language)}`}
                  disabled={preferences.identifiers.length === 1}
                  onClick={() => setPreferences((current) => removeZone(current, zone))}>
                  <Trash2 size={14} />
                </button>
              </div>
            );
          })}
        </section>
        <footer className="window-footer">
          <p>{labels.trayHint}</p>
          <HaloButton onClick={() => setView("add")} staggerLabel={false}>{labels.addZone}</HaloButton>
        </footer>
      </>}

      {view === "add" && <>
        <label className="search-box">
          <Search size={17} aria-hidden="true" />
          <input autoFocus value={query} onChange={(event) => setQuery(event.target.value)} placeholder={labels.search} aria-label={labels.search} />
        </label>
        <section className="search-results">
          {matches.length ? matches.map((zone) => {
            const selected = preferences.identifiers.includes(zone);
            return <button className="result-row" disabled={selected} key={zone} onClick={() => add(zone)}>
              <span><strong>{cityName(zone, preferences.language)}</strong><small>{zone}</small></span>
              {selected ? <Check size={18} aria-label={labels.selected} /> : <Plus size={18} aria-hidden="true" />}
            </button>;
          }) : <p className="empty-state">{labels.noResults}</p>}
        </section>
      </>}

      {view === "settings" && <section className="settings-list">
        <h2>{labels.display}</h2>
        <label className="setting-line">{labels.showDate}<input type="checkbox" checked={preferences.showDate}
          onChange={(event) => setPreferences((current) => ({ ...current, showDate: event.target.checked }))} /></label>
        <label className="setting-line">{labels.showSeconds}<input type="checkbox" checked={preferences.showSeconds}
          onChange={(event) => setPreferences((current) => ({ ...current, showSeconds: event.target.checked }))} /></label>
        <label className="setting-line">{labels.startAtLogin}<input type="checkbox" checked={autostart}
          disabled={!isTauri()} onChange={() => void toggleAutostart()} /></label>
        <label className="setting-line">{labels.globe}<input type="checkbox" checked={preferences.showGlobe}
          onChange={(event) => setPreferences((current) => ({ ...current, showGlobe: event.target.checked }))} /></label>
        <p className="setting-hint">{labels.globeHint}</p>
        <label className="setting-line">{labels.language}
          <select value={preferences.language} onChange={(event) => setPreferences((current) => ({
            ...current, language: event.target.value as ClockPreferences["language"],
          }))}>
            <option value="system">System</option><option value="zh-Hans">简体中文</option>
            <option value="zh-Hant">繁體中文</option><option value="en">English</option>
          </select>
        </label>
        <p className="setting-hint">{labels.traySystemHint}</p>
      </section>}
      {error && <p className="error-banner" role="alert">{error}</p>}
    </main>
  );
}

export default App;
