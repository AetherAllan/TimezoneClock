import AppKit
import Combine
import Observation
import ServiceManagement
import SwiftUI

@MainActor
@Observable
final class ClockStore {
    var now = Date()
    var selection: ClockSelection {
        didSet {
            UserDefaults.standard.set(selection.identifiers, forKey: "selectedTimeZones")
            UserDefaults.standard.set(selection.primary, forKey: "primaryTimeZone")
        }
    }
    var loginStatus = SMAppService.mainApp.status
    var loginError: String?
    var preferences: ClockPreferences {
        didSet {
            if let data = try? JSONEncoder().encode(preferences) {
                UserDefaults.standard.set(data, forKey: "clockPreferences")
            }
            if oldValue.schedule != preferences.schedule {
                appearance.configure(preferences.schedule,
                    askPermission: !oldValue.schedule.enabled && preferences.schedule.enabled)
            }
            if oldValue.showSeconds != preferences.showSeconds { restartClock() }
        }
    }
    let appearance = AppearanceController()
    private var subscriptions = Set<AnyCancellable>()
    @ObservationIgnored private var clockTimer: AnyCancellable?
    @ObservationIgnored weak var menuPanelWindow: NSWindow?

    init() {
        let defaults = UserDefaults.standard
        preferences = ClockPreferences.load(from: defaults.data(forKey: "clockPreferences"))
        selection = ClockSelection(
            identifiers: defaults.stringArray(forKey: "selectedTimeZones") ?? ClockZone.defaultIdentifiers,
            primary: defaults.string(forKey: "primaryTimeZone") ?? "Asia/Shanghai"
        )

        // Notifications can arrive off the main thread; deliver UI updates on the main run loop.
        Publishers.Merge(
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification),
            NotificationCenter.default.publisher(for: NSNotification.Name.NSSystemClockDidChange)
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            MainActor.assumeIsolated {
                self?.restartClock()
            }
        }
        .store(in: &subscriptions)

        if !defaults.bool(forKey: "didInitializeLoginItem") {
            defaults.set(true, forKey: "didInitializeLoginItem")
            setLaunchAtLogin(true)
        }
        appearance.configure(preferences.schedule)
        restartClock()
    }

    private func restartClock() {
        clockTimer?.cancel()
        now = Date()
        appearance.tick(at: now, force: true)
        let timer = Timer(fire: preferences.nextRefresh(after: now), interval: preferences.refreshInterval,
                          repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.now = Date()
                self.appearance.tick(at: self.now)
            }
        }
        timer.tolerance = preferences.showSeconds ? 0.1 : 1
        clockTimer = AnyCancellable { timer.invalidate() }
        RunLoop.main.add(timer, forMode: .common)
    }

    var language: AppLanguage { preferences.language }
    func text(_ key: String) -> String { language.text(key) }

    var menuLabel: String {
        guard let zone = ClockZone(selection.primary) else { return "TimezoneClock" }
        let day = preferences.showDate ? zone.day(at: now, language: language) + " " : ""
        return "\(zone.name(language: language)) \(day)\(zone.time(at: now, seconds: preferences.showSeconds))"
    }

    var launchesAtLogin: Bool { loginStatus == .enabled || loginStatus == .requiresApproval }

    func refreshLoginStatus() { loginStatus = SMAppService.mainApp.status }

    func dismissMenuPanel() { menuPanelWindow?.close() }

    func setLaunchAtLogin(_ enabled: Bool) {
        loginError = nil
        refreshLoginStatus()
        do {
            if enabled {
                if !launchesAtLogin { try SMAppService.mainApp.register() }
            } else if loginStatus != .notRegistered {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginError = error.localizedDescription
        }
        refreshLoginStatus()
    }
}

@main
struct TimezoneClockApp: App {
    @State private var store = ClockStore()

    var body: some Scene {
        MenuBarExtra {
            ClockPanel(store: store)
        } label: {
            ClockMenuLabel(store: store)
        }
        .menuBarExtraStyle(.window)
        Settings {
            ClockSettingsView(store: store)
                .environment(\.locale, store.language.locale)
        }
    }
}

private struct ClockMenuLabel: View {
    let store: ClockStore
    var body: some View {
        let label = store.menuLabel
        Text(label).monospacedDigit().accessibilityLabel(label)
    }
}

struct ClockPanel: View {
    @Bindable var store: ClockStore
    @State private var isAdding = false
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ClockPanelSurface(style: store.preferences.interfaceStyle) {
            panelContent
        }
        .background(ClockPanelWindowReader(store: store).allowsHitTesting(false))
        .environment(\.locale, store.language.locale)
        .onAppear {
            store.now = Date()
            store.refreshLoginStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.refreshLoginStatus()
        }
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(store.text("World Clock"), systemImage: "globe")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer()
                Button {
                    isAdding.toggle()
                } label: {
                    Image(systemName: isAdding ? "xmark" : "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .modifier(ClockActionStyle(style: store.preferences.interfaceStyle))
                .buttonBorderShape(.circle)
                .help(store.text(isAdding ? "Close Search" : "Add Time Zone"))
                .accessibilityLabel(store.text(isAdding ? "Close Search" : "Add Time Zone"))
            }
            .padding(.horizontal, 2)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(store.selection.zones) { zone in
                        ClockZoneRow(zone: zone, store: store)
                    }
                }
                .padding(.horizontal, 1)
            }
            .frame(height: min(CGFloat(store.selection.identifiers.count) * 64, isAdding ? 154 : 308))

            if isAdding {
                Divider()
                ClockZoneSearch(store: store)
            }

            Divider().opacity(0.4)
            HStack(spacing: 8) {
                Toggle(store.text("Launch at Login"), isOn: Binding(
                    get: { store.launchesAtLogin }, set: { store.setLaunchAtLogin($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: 11, weight: .medium))
                Spacer()
                Button {
                    store.dismissMenuPanel()
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 22, height: 22)
                }
                .modifier(ClockActionStyle(style: store.preferences.interfaceStyle))
                .buttonBorderShape(.circle)
                .help(store.text("Settings"))
                .accessibilityLabel(store.text("Settings"))
                .keyboardShortcut(",")
                Button(store.text("Quit")) { NSApplication.shared.terminate(nil) }
                    .modifier(ClockActionStyle(style: store.preferences.interfaceStyle))
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .keyboardShortcut("q")
            }
            .padding(.horizontal, 2)
            if store.loginStatus == .requiresApproval {
                Text(store.text("Launch at login needs system approval"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = store.loginError {
                Text(store.text("Login setting failed:") + " " + error)
                    .font(.caption).foregroundStyle(.red).textSelection(.enabled)
            }
            if store.loginStatus == .requiresApproval || store.loginError != nil {
                Button(store.text("Open Login Items Settings")) { SMAppService.openSystemSettingsLoginItems() }
                    .font(.caption)
            }
        }
        .padding(11)
        .frame(width: 280)
    }
}

// Capture this popup's window so opening settings never closes another app window.
private struct ClockPanelWindowReader: NSViewRepresentable {
    let store: ClockStore

    func makeNSView(context: Context) -> WindowView {
        let view = WindowView(frame: .zero)
        view.store = store
        return view
    }

    func updateNSView(_ view: WindowView, context: Context) {
        store.menuPanelWindow = view.window
    }

    final class WindowView: NSView {
        weak var store: ClockStore?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            store?.menuPanelWindow = window
        }
    }
}

private struct ClockZoneRow: View {
    let zone: ClockZone
    @Bindable var store: ClockStore

    var body: some View {
        HStack(spacing: 8) {
            Button {
                store.selection.pin(zone.id)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(zone.name(language: store.language))
                            .font(.system(size: 12, weight: .medium)).lineLimit(1)
                        if store.selection.primary == zone.id {
                            Image(systemName: "pin.fill").font(.caption).foregroundStyle(.tint)
                                .accessibilityLabel(store.text("Pinned"))
                        }
                        Spacer(minLength: 8)
                        Text(zone.time(at: store.now, seconds: store.preferences.showSeconds))
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .fixedSize()
                    }
                    HStack {
                        Text(zone.day(at: store.now, language: store.language))
                        Spacer()
                        Text(zone.offset(at: store.now))
                    }
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("\(zone.id) · \(store.text("Show in Menu Bar"))")
            .accessibilityAddTraits(store.selection.primary == zone.id ? .isSelected : [])
            .accessibilityLabel("\(zone.name(language: store.language)), \(zone.day(at: store.now, language: store.language)), \(zone.time(at: store.now, seconds: store.preferences.showSeconds)), \(store.text("Show in Menu Bar"))")

            Button { store.selection.remove(zone.id) } label: {
                Image(systemName: "minus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(store.selection.identifiers.count == 1)
            .help(store.text("Remove Time Zone"))
            .accessibilityLabel("\(store.text("Remove Time Zone")) \(zone.name(language: store.language))")
        }
        .padding(8)
        .modifier(ClockCardSurface(style: store.preferences.interfaceStyle,
                                  selected: store.selection.primary == zone.id))
    }
}

private struct ClockZoneSearch: View {
    @Bindable var store: ClockStore
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        let results = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ClockZone.available : ClockZone.available.filter { $0.matches(query, language: store.language) }
        VStack(alignment: .leading, spacing: 8) {
            TextField(store.text("Search city or time zone identifier"), text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .accessibilityLabel(store.text("Search Time Zones"))

            if results.isEmpty {
                Text(store.text("No matching time zones"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 42)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(results) { zone in
                            let isSelected = store.selection.identifiers.contains(zone.id)
                            Button {
                                store.selection.add(zone.id)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(zone.name(language: store.language))
                                        Text(zone.id).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: isSelected ? "checkmark" : "plus.circle")
                                }
                                .padding(6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(isSelected)
                            .accessibilityLabel("\(zone.name(language: store.language)), \(store.text(isSelected ? "Already Added" : "Add Time Zone")), \(zone.id)")
                        }
                    }
                }
                .frame(height: min(CGFloat(results.count) * 50, 126))
            }
        }
        .onAppear { searchFocused = true }
    }
}
