import AppKit
import ServiceManagement
import SwiftUI

struct ClockSettingsView: View {
    @Bindable var store: ClockStore
    @State private var query = ""

    private var scheduleZones: [ClockZone] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return ClockZone.available }
        return ClockZone.available.filter {
            $0.id == store.preferences.schedule.timeZoneID || $0.matches(query, language: store.language)
        }
    }

    var body: some View {
        Form {
            Section(store.text("Display")) {
                Picker(store.text("Language"), selection: $store.preferences.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language == .system ? store.text("Follow System") : language.title).tag(language)
                    }
                }
                Toggle(store.text("Show date in menu bar"), isOn: $store.preferences.showDate)
                Toggle(store.text("Show seconds"), isOn: $store.preferences.showSeconds)
                Text(store.text("Long labels need more menu bar space. Dates always appear in the clock panel."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(store.text("System Appearance Schedule")) {
                Toggle(store.text("Enable appearance schedule"), isOn: $store.preferences.schedule.enabled)
                TextField(store.text("Search city or time zone identifier"), text: $query)
                LabeledContent(store.text("Schedule time zone")) {
                    ClockZonePicker(zones: scheduleZones, language: store.language,
                                    selection: $store.preferences.schedule.timeZoneID)
                        .frame(maxWidth: 360)
                }
                timePicker("Switch to Light at", minute: $store.preferences.schedule.lightMinute)
                timePicker("Switch to Dark at", minute: $store.preferences.schedule.darkMinute)
                Text(store.appearance.status.text(language: store.language))
                    .font(.callout).textSelection(.enabled)
                    .accessibilityIdentifier("appearanceStatus")
                Text(store.text("Uses the selected time zone, including daylight saving time. Manual changes last until the next transition. Disabling keeps the current appearance."))
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(store.text("Check / Request Access")) {
                        store.appearance.configure(store.preferences.schedule, askPermission: true)
                    }
                    .disabled(!store.preferences.schedule.enabled || !store.preferences.schedule.isValid)
                    Button(store.text("Appearance Settings")) {
                        openSystemSettings("com.apple.Appearance-Settings.extension")
                    }
                    Button(store.text("Automation Settings")) {
                        openSystemSettings("com.apple.preference.security?Privacy_Automation")
                    }
                }
                .controlSize(.small)
            }
            Section {
                Toggle(store.text("Launch at Login"), isOn: Binding(
                    get: { store.launchesAtLogin }, set: { store.setLaunchAtLogin($0) }
                ))
                if store.loginStatus == .requiresApproval {
                    Text(store.text("Launch at login needs system approval"))
                }
                if let error = store.loginError {
                    Text(store.text("Login setting failed:") + " " + error).foregroundStyle(.red)
                }
                Button(store.text("Open Login Items Settings")) { SMAppService.openSystemSettingsLoginItems() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 660)
        .onAppear {
            store.refreshLoginStatus()
            store.appearance.tick(at: Date(), force: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.refreshLoginStatus()
            store.appearance.tick(at: Date(), force: true)
        }
    }

    private func timePicker(_ label: String, minute: Binding<Int>) -> some View {
        // A UTC reference date represents a wall-clock time, independent of the system zone.
        DatePicker(store.text(label), selection: Binding(
            get: { Date(timeIntervalSinceReferenceDate: Double(minute.wrappedValue * 60)) },
            set: { date in
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = .gmt
                let parts = calendar.dateComponents([.hour, .minute], from: date)
                minute.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        ), displayedComponents: .hourAndMinute)
        .environment(\.timeZone, .gmt)
        .environment(\.locale, Locale(identifier: "en_GB"))
    }

    private func openSystemSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:\(pane)") { NSWorkspace.shared.open(url) }
    }
}

// A large SwiftUI menu creates a view graph for every item when opened. Native text menu
// items keep the complete time-zone list without that per-item SwiftUI graph.
private struct ClockZonePicker: NSViewRepresentable {
    let zones: [ClockZone]
    let language: AppLanguage
    @Binding var selection: String

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectZone(_:))
        button.autoenablesItems = false
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.cell?.lineBreakMode = .byTruncatingMiddle
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.selection = $selection
        let titles = zones.map { "\($0.name(language: language)) · \($0.id)" }
        if button.itemTitles != titles {
            button.removeAllItems()
            for (zone, title) in zip(zones, titles) {
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.representedObject = zone.id
                button.menu?.addItem(item)
            }
        }
        button.selectItem(at: zones.firstIndex { $0.id == selection } ?? -1)
        button.setAccessibilityLabel(language.text("Schedule time zone"))
    }

    @MainActor
    final class Coordinator: NSObject {
        var selection: Binding<String>
        init(selection: Binding<String>) { self.selection = selection }

        @objc func selectZone(_ sender: NSPopUpButton) {
            guard let identifier = sender.selectedItem?.representedObject as? String else { return }
            selection.wrappedValue = identifier
        }
    }
}
