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
    private var subscriptions = Set<AnyCancellable>()

    init() {
        let defaults = UserDefaults.standard
        selection = ClockSelection(
            identifiers: defaults.stringArray(forKey: "selectedTimeZones") ?? ClockZone.defaultIdentifiers,
            primary: defaults.string(forKey: "primaryTimeZone") ?? "Asia/Shanghai"
        )

        Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] date in
                MainActor.assumeIsolated { self?.now = date }
            }
            .store(in: &subscriptions)

        // Notifications can arrive off the main thread; deliver UI updates on the main run loop.
        Publishers.Merge(
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification),
            NotificationCenter.default.publisher(for: NSNotification.Name.NSSystemClockDidChange)
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            MainActor.assumeIsolated { self?.now = Date() }
        }
        .store(in: &subscriptions)

        if !defaults.bool(forKey: "didInitializeLoginItem") {
            defaults.set(true, forKey: "didInitializeLoginItem")
            setLaunchAtLogin(true)
        }
    }

    var menuLabel: String {
        guard let zone = ClockZone(selection.primary) else { return "时区时钟" }
        return "\(zone.name) \(zone.time(at: now))"
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
            loginError = "登录启动设置失败：\(error.localizedDescription)"
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
    }
}

struct ClockPanel: View {
    @Bindable var store: ClockStore
    @State private var isAdding = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var results: [ClockZone] { ClockZone.available.filter { $0.matches(query) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("世界时钟", systemImage: "clock")
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
                .help(isAdding ? "收起添加时区" : "添加时区")
                .accessibilityLabel(isAdding ? "收起添加时区" : "添加时区")
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
                TextField("搜索城市或时区标识", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .accessibilityLabel("搜索时区")

                if results.isEmpty {
                    Text("没有匹配的时区")
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
                                            Text(zone.name)
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
                                .accessibilityLabel(isSelected ? "\(zone.name)，已添加" : "添加\(zone.name)，\(zone.id)")
                            }
                        }
                    }
                    .frame(height: min(CGFloat(results.count) * 50, 180))
                }
            }

            Divider()
            HStack {
                Toggle("登录时启动", isOn: Binding(
                    get: { store.launchesAtLogin }, set: { store.setLaunchAtLogin($0) }
                ))
                .toggleStyle(.checkbox)
                Spacer()
                Button("退出") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
            if store.loginStatus == .requiresApproval {
                Text("登录启动等待系统批准")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = store.loginError {
                Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
            }
            if store.loginStatus == .requiresApproval || store.loginError != nil {
                Button("打开登录项设置") { SMAppService.openSystemSettingsLoginItems() }
                    .font(.caption)
            }
        }
        .padding(16)
        .frame(width: 370)
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
                        Text(zone.name).lineLimit(1)
                        if store.selection.primary == zone.id {
                            Image(systemName: "pin.fill").font(.caption).foregroundStyle(.tint)
                        }
                        Spacer(minLength: 8)
                        Text(zone.time(at: store.now))
                            .font(.system(size: 21, weight: .medium, design: .rounded))
                            .monospacedDigit()
                    }
                    HStack {
                        Text(zone.day(at: store.now))
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
            .help("\(zone.id) · 点击设为常驻时区")
            .accessibilityLabel("\(zone.name)，\(zone.day(at: store.now))，\(zone.time(at: store.now))，设为常驻时区")

            Button { store.selection.remove(zone.id) } label: {
                Image(systemName: "minus.circle").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .disabled(store.selection.identifiers.count == 1)
            .help("移除此时区")
            .accessibilityLabel("移除\(zone.name)")
        }
    }
}
