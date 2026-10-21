use std::{sync::Mutex, thread, time::Duration};

use chrono::{Timelike, Utc};
use chrono_tz::Tz;
use tauri::{
    AppHandle, Manager, WindowEvent,
    image::Image,
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
};
use tauri_plugin_autostart::MacosLauncher;
use tauri_plugin_positioner::{Position, WindowExt};

const TRAY_ID: &str = "clock";
const DEFAULT_ZONE: &str = "Asia/Shanghai";
const LOGICAL_SIZE: usize = 16;
const SCALE: usize = 4; // High-DPI source; Windows chooses the physical tray slot size.

struct ClockState {
    primary_zone: Mutex<String>,
}

impl Default for ClockState {
    fn default() -> Self {
        Self {
            primary_zone: Mutex::new(DEFAULT_ZONE.to_string()),
        }
    }
}

// Five-pixel-wide, seven-pixel-high digits. Two rows keep HH and mm as legible as
// the Windows notification area's small, OS-controlled icon slot permits.
const DIGITS: [[u8; 7]; 10] = [
    [
        0b01110, 0b10001, 0b10011, 0b10101, 0b11001, 0b10001, 0b01110,
    ],
    [
        0b00100, 0b01100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110,
    ],
    [
        0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0b01000, 0b11111,
    ],
    [
        0b11110, 0b00001, 0b00001, 0b01110, 0b00001, 0b00001, 0b11110,
    ],
    [
        0b00010, 0b00110, 0b01010, 0b10010, 0b11111, 0b00010, 0b00010,
    ],
    [
        0b11111, 0b10000, 0b10000, 0b11110, 0b00001, 0b00001, 0b11110,
    ],
    [
        0b01110, 0b10000, 0b10000, 0b11110, 0b10001, 0b10001, 0b01110,
    ],
    [
        0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b01000, 0b01000,
    ],
    [
        0b01110, 0b10001, 0b10001, 0b01110, 0b10001, 0b10001, 0b01110,
    ],
    [
        0b01110, 0b10001, 0b10001, 0b01111, 0b00001, 0b00001, 0b01110,
    ],
];

fn paint(pixels: &mut [u8], x: usize, y: usize, color: [u8; 4]) {
    for dy in 0..SCALE {
        for dx in 0..SCALE {
            let side = LOGICAL_SIZE * SCALE;
            let index = ((y * SCALE + dy) * side + x * SCALE + dx) * 4;
            pixels[index..index + 4].copy_from_slice(&color);
        }
    }
}

fn paint_digit(pixels: &mut [u8], digit: u32, x: usize, y: usize, color: [u8; 4]) {
    for (dy, row) in DIGITS[digit as usize].iter().enumerate() {
        for dx in 0..5 {
            if row & (1 << (4 - dx)) != 0 {
                paint(pixels, x + dx, y + dy, color);
            }
        }
    }
}

fn clock_icon(hour: u32, minute: u32) -> Image<'static> {
    let side = LOGICAL_SIZE * SCALE;
    let mut pixels = vec![0; side * side * 4];
    for y in 0..LOGICAL_SIZE {
        for x in 0..LOGICAL_SIZE {
            let background = if y < 8 {
                [13, 25, 47, 255]
            } else {
                [9, 17, 34, 255]
            };
            paint(&mut pixels, x, y, background);
        }
    }
    let hour_color = [105, 241, 215, 255];
    let minute_color = [250, 252, 255, 255];
    paint_digit(&mut pixels, hour / 10, 2, 0, hour_color);
    paint_digit(&mut pixels, hour % 10, 9, 0, hour_color);
    paint_digit(&mut pixels, minute / 10, 2, 9, minute_color);
    paint_digit(&mut pixels, minute % 10, 9, 9, minute_color);
    Image::new_owned(pixels, side as u32, side as u32)
}

fn refresh_tray(app: &AppHandle) -> Result<(), String> {
    let state = app.state::<ClockState>();
    let zone = state
        .primary_zone
        .lock()
        .map_err(|_| "clock state is unavailable")?
        .clone();
    let time_zone: Tz = zone.parse().map_err(|_| "invalid time zone")?;
    let now = Utc::now().with_timezone(&time_zone);
    if let Some(tray) = app.tray_by_id(TRAY_ID) {
        tray.set_icon(Some(clock_icon(now.hour(), now.minute())))
            .map_err(|error| error.to_string())?;
        tray.set_tooltip(Some(format!("{zone} · {}", now.format("%Y-%m-%d %H:%M"))))
            .map_err(|error| error.to_string())?;
    }
    Ok(())
}

#[tauri::command]
fn set_primary_zone(app: AppHandle, zone: String) -> Result<(), String> {
    let _: Tz = zone.parse().map_err(|_| "unsupported time zone")?;
    {
        let state = app.state::<ClockState>();
        *state
            .primary_zone
            .lock()
            .map_err(|_| "clock state is unavailable")? = zone;
    }
    refresh_tray(&app)
}

#[tauri::command]
fn hide_popup(app: AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.hide();
    }
}

pub fn run() {
    tauri::Builder::default()
        .manage(ClockState::default())
        .plugin(tauri_plugin_positioner::init())
        .plugin(tauri_plugin_autostart::init(
            MacosLauncher::LaunchAgent,
            None,
        ))
        .invoke_handler(tauri::generate_handler![set_primary_zone, hide_popup])
        .setup(|app| {
            let window = app
                .get_webview_window("main")
                .ok_or("popup window missing")?;
            let window_for_events = window.clone();
            window.on_window_event(move |event| match event {
                WindowEvent::Focused(false) => {
                    let _ = window_for_events.hide();
                }
                WindowEvent::CloseRequested { api, .. } => {
                    api.prevent_close();
                    let _ = window_for_events.hide();
                }
                _ => {}
            });

            let quit = MenuItem::with_id(app, "quit", "退出 TimezoneClock", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&quit])?;
            TrayIconBuilder::with_id(TRAY_ID)
                .icon(clock_icon(0, 0))
                .menu(&menu)
                .show_menu_on_left_click(false)
                .on_menu_event(|app, event| {
                    if event.id.as_ref() == "quit" {
                        app.exit(0);
                    }
                })
                .on_tray_icon_event(|tray, event| {
                    let app = tray.app_handle();
                    tauri_plugin_positioner::on_tray_event(app, &event);
                    if let TrayIconEvent::Click {
                        button: MouseButton::Left,
                        button_state: MouseButtonState::Up,
                        ..
                    } = event
                    {
                        if let Some(window) = app.get_webview_window("main") {
                            let _ = window.move_window(Position::TrayCenter);
                            let _ = window.show();
                            let _ = window.set_focus();
                        }
                    }
                })
                .build(app)?;

            refresh_tray(app.handle()).map_err(std::io::Error::other)?;
            let handle = app.handle().clone();
            thread::spawn(move || {
                let mut last_key = String::new();
                loop {
                    let zone = match handle.state::<ClockState>().primary_zone.lock() {
                        Ok(value) => value.clone(),
                        Err(_) => break,
                    };
                    let now = Utc::now();
                    let key = format!("{zone}:{}", now.timestamp() / 60);
                    if key != last_key {
                        if refresh_tray(&handle).is_err() {
                            break;
                        }
                        last_key = key;
                    }
                    thread::sleep(Duration::from_secs(1));
                }
            });
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running TimezoneClock");
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn clock_icon_is_high_dpi_rgba() {
        let icon = clock_icon(23, 59);
        assert_eq!(icon.width(), (LOGICAL_SIZE * SCALE) as u32);
        assert_eq!(icon.height(), (LOGICAL_SIZE * SCALE) as u32);
        assert_eq!(
            icon.rgba().len(),
            LOGICAL_SIZE * LOGICAL_SIZE * SCALE * SCALE * 4
        );
    }

    #[test]
    fn daylight_saving_changes_new_york_local_hour() {
        let zone: Tz = "America/New_York".parse().unwrap();
        let before = chrono::DateTime::parse_from_rfc3339("2026-03-08T06:59:00Z")
            .unwrap()
            .with_timezone(&zone);
        let after = chrono::DateTime::parse_from_rfc3339("2026-03-08T07:01:00Z")
            .unwrap()
            .with_timezone(&zone);
        assert_eq!((before.hour(), after.hour()), (1, 3));
    }
}
