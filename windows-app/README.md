# TimezoneClock for Windows

A Windows notification-area world clock built with Tauri 2, React, TypeScript, Tailwind and Cult UI. The optional globe is rendered with Three.js only while the popup is focused. The existing macOS SwiftUI app remains independent.

## What the tray icon shows

The chosen time zone's **hours above minutes** appear in a high-contrast, high-DPI tray icon. The tooltip shows its IANA time-zone ID, date and full time. Left-click the icon to open the world clock; right-click and choose **退出 TimezoneClock** to quit. Click a zone in the popup to pin it. The popup also supports adding/removing time zones, three languages, date/seconds options, an optional 3D globe, and opt-in launch at login.

**Windows decides the physical size and visibility of tray icons.** This app cannot enlarge its own taskbar slot or insert text beside it. To keep it visible rather than in the overflow menu, go to **Settings → Personalization → Taskbar → Other system tray icons**, then enable TimezoneClock. At 100% display scaling the icon is still small; the two-line layout favors readability over squeezing `HH:mm` onto one line. The icon updates once per minute (the popup may show seconds).

Time-zone conversions use IANA IDs and account for daylight saving time. The Windows app does **not** change the machine's system time zone or system-wide light/dark mode. Settings are stored locally in this app's WebView profile; they are not automatically copied from the macOS app.

## Run or build

This repository contains an unsigned local build at `src-tauri/target/release/bundle/nsis/TimezoneClock_0.1.0_x64-setup.exe` after building. `src-tauri/target/` is intentionally git-ignored: clone users must build their own copy. Install before enabling **Launch at login**, so the registered startup path stays stable.

Requirements: Windows 10/11, WebView2, Node.js, Rust with the MSVC toolchain, and Visual Studio C++ Build Tools. From `windows-app/`:

```sh
npm ci
npm test
npm run build
npm run test:ui                  # optional; requires local Chrome or CHROME_PATH
cargo test --manifest-path src-tauri/Cargo.toml --lib
npm run tauri -- build --bundles nsis
```

Use `npm run tauri -- dev` while developing. The popup starts hidden: open it by left-clicking the tray icon. The `test:ui` smoke test uses a separate headless Chrome instance and does not use a personal browser profile.

The Cult UI Halo Button source is installed under `src/components/ui/halo-button.tsx` through the official shadcn registry. The 3D globe is code-split and off by default to keep background activity low.
