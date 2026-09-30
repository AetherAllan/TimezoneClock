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
        }
    }
    let appearance = AppearanceController()
    private var subscriptions = Set<AnyCancellable>()

    init() {
        let defaults = UserDefaults.standard
        preferences = ClockPreferences.load(from: defaults.data(forKey: "clockPreferences"))
        selection = ClockSelection(
            identifiers: defaults.stringArray(forKey: "selectedTimeZones") ?? ClockZone.defaultIdentifiers,
            primary: defaults.string(forKey: "primaryTimeZone") ?? "Asia/Shanghai"
        )

        Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] date in
                MainActor.assumeIsolated {
                    self?.now = date
                    self?.appearance.tick(at: date)
                }
            }
            .store(in: &subscriptions)

        // Notifications can arrive off the main thread; deliver UI updates on the main run loop.
        Publishers.Merge(
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification),
            NotificationCenter.default.publisher(for: NSNotification.Name.NSSystemClockDidChange)
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            MainActor.assumeIsolated {
                self?.now = Date()
                self?.appearance.tick(at: Date(), force: true)
            }
        }
        .store(in: &subscriptions)

        if !defaults.bool(forKey: "didInitializeLoginItem") {
            defaults.set(true, forKey: "didInitializeLoginItem")
            setLaunchAtLogin(true)
        }
        appearance.configure(preferences.schedule)
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
            Text(store.menuLabel)
                .monospacedDigit()
                .accessibilityLabel(store.menuLabel)
        }
        .menuBarExtraStyle(.window)
        Settings {
            ClockSettingsView(store: store)
                .environment(\.locale, store.language.locale)
        }
    }
}

struct ClockPanel: View {
    @Bindable var store: ClockStore
    @State private var isAdding = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @Environment(\.openSettings) private var openSettings

    private var results: [ClockZone] { ClockZone.available.filter { $0.matches(query, language: store.language) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(store.text("World Clock"), systemImage: "clock")
                    .font(.headline)
                Spacer()
                Button {
                    isAdding.toggle()
                    query = ""
                    searchFocused = isAdding
                } label: {
                    Image(systemName: isAdding ? "xmark" : "plus")
                }
                .buttonStyle(.borderless)
                .help(store.text(isAdding ? "Close Search" : "Add Time Zone"))
                .accessibilityLabel(store.text(isAdding ? "Close Search" : "Add Time Zone"))
            }

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(store.selection.zones) { zone in
                        clockRow(zone)
                    }
                }
            }
            .frame(height: min(CGFloat(store.selection.identifiers.count) * 66, 330))

            if isAdding {
                Divider()
                TextField(store.text("Search city or time zone identifier"), text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .accessibilityLabel(store.text("Search Time Zones"))

                if results.isEmpty {
                    Text(store.text("No matching time zones"))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 60)
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
                    .frame(height: min(CGFloat(results.count) * 50, 180))
                }
            }

            Divider()
            HStack {
                Toggle(store.text("Launch at Login"), isOn: Binding(
                    get: { store.launchesAtLogin }, set: { store.setLaunchAtLogin($0) }
                ))
                .toggleStyle(.checkbox)
                Spacer()
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                } label: { Image(systemName: "gearshape") }
                .help(store.text("Settings"))
                .accessibilityLabel(store.text("Settings"))
                .keyboardShortcut(",")
                Button(store.text("Quit")) { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
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
        .padding(16)
        .frame(width: 370)
        .environment(\.locale, store.language.locale)
        .onAppear {
            store.now = Date()
            store.refreshLoginStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.refreshLoginStatus()
        }
    }

    private func clockRow(_ zone: ClockZone) -> some View {
        HStack(spacing: 10) {
            Button {
                store.selection.pin(zone.id)
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(zone.name(language: store.language)).lineLimit(1)
                        if store.selection.primary == zone.id {
                            Image(systemName: "pin.fill").font(.caption).foregroundStyle(.tint)
                        }
                        Spacer(minLength: 8)
                        Text(zone.time(at: store.now, seconds: store.preferences.showSeconds))
                            .font(.system(size: 21, weight: .medium, design: .rounded))
                            .monospacedDigit()
                    }
                    HStack {
                        Text(zone.day(at: store.now, language: store.language))
                        Spacer()
                        Text(zone.offset(at: store.now))
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                .padding(8)
                .background(store.selection.primary == zone.id ? Color.accentColor.opacity(0.08) : .clear,
                            in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("\(zone.id) · \(store.text("Show in Menu Bar"))")
            .accessibilityLabel("\(zone.name(language: store.language)), \(zone.day(at: store.now, language: store.language)), \(zone.time(at: store.now, seconds: store.preferences.showSeconds)), \(store.text("Show in Menu Bar"))")

            Button { store.selection.remove(zone.id) } label: {
                Image(systemName: "minus.circle").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .disabled(store.selection.identifiers.count == 1)
            .help(store.text("Remove Time Zone"))
            .accessibilityLabel("\(store.text("Remove Time Zone")) \(zone.name(language: store.language))")
        }
    }
}
