import AppKit
import Carbon
import Observation

enum AppearanceStatus {
    case off, checking, automatic, manualOverride, invalidSchedule
    case scheduled(dark: Bool)
    case permission(code: Int32)
    case failed(String)

    func text(language: AppLanguage) -> String {
        switch self {
        case .off: language.text("Scheduling is off")
        case .checking: language.text("Checking system appearance…")
        case .automatic: language.text("Choose Light or Dark in macOS Appearance to let this schedule take over.")
        case .manualOverride: language.text("Manual appearance change kept until the next scheduled transition.")
        case .invalidSchedule: language.text("Light and dark times must be different.")
        case .scheduled(let dark): language.text(dark ? "Scheduled appearance: Dark" : "Scheduled appearance: Light")
        case .permission(let code): language.text("Automation access is required. Allow TimezoneClock to control System Events.") + " (\(code))"
        case .failed(let error): language.text("Appearance update failed:") + " " + error
        }
    }
}

private struct AppearanceError: Error {
    let code: Int32
    let message: String
}

// Each script is created and executed on this serial actor; permission prompts never block the UI.
private actor SystemAppearance {
    func read(askPermission: Bool) throws -> Bool {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.systemevents")
        let permission = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard,
                                                               askPermission)
        guard permission == noErr else { throw AppearanceError(code: permission, message: "") }
        try Task.checkCancellation()
        return try execute("tell application id \"com.apple.systemevents\" to get dark mode of appearance preferences").booleanValue
    }

    func write(dark: Bool) throws {
        try Task.checkCancellation()
        _ = try execute("tell application id \"com.apple.systemevents\" to set dark mode of appearance preferences to \(dark ? "true" : "false")")
    }

    private func execute(_ source: String) throws -> NSAppleEventDescriptor {
        guard let script = NSAppleScript(source: source) else {
            throw AppearanceError(code: -1, message: "Cannot create appearance script")
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if error != nil {
            throw AppearanceError(code: (error?[NSAppleScript.errorNumber] as? NSNumber)?.int32Value ?? -1,
                                  message: error?[NSAppleScript.errorMessage] as? String ?? "Apple event failed")
        }
        return result
    }
}

@MainActor
@Observable
final class AppearanceController {
    private(set) var status: AppearanceStatus = .off
    private var schedule = AppearanceSchedule()
    private var run = AppearanceRun()
    private var lastMinute: Int?
    private var task: Task<Void, Never>?
    private let system = SystemAppearance()
    private var generation = 0

    func configure(_ schedule: AppearanceSchedule, askPermission: Bool = false) {
        task?.cancel()
        task = nil
        generation += 1
        if self.schedule != schedule { run = AppearanceRun() }
        self.schedule = schedule
        lastMinute = nil
        status = schedule.enabled ? .checking : .off
        tick(at: Date(), force: true, askPermission: askPermission)
    }

    func tick(at now: Date, force: Bool = false, askPermission: Bool = false) {
        guard schedule.enabled, task == nil else { return }
        let minute = Int(now.timeIntervalSince1970 / 60)
        guard force || lastMinute != minute else { return }
        lastMinute = minute
        guard let period = schedule.period(at: now) else { status = .invalidSchedule; return }
        let currentGeneration = generation
        task = Task { [weak self] in
            guard let self else { return }
            defer { if generation == currentGeneration { task = nil } }
            do {
                // Permission preflight requires a running target. Launch the system helper quietly.
                if NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systemevents").isEmpty {
                    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systemevents") else {
                        throw AppearanceError(code: Int32(procNotFound), message: "System Events is unavailable")
                    }
                    let configuration = NSWorkspace.OpenConfiguration()
                    configuration.activates = false
                    _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
                }
                guard !Task.isCancelled, generation == currentGeneration else { return }
                let actualDark = try await system.read(askPermission: askPermission)
                guard !Task.isCancelled, generation == currentGeneration else { return }
                // Request access even while macOS Auto is enabled, so the app can appear in
                // Automation settings. Only appearance writes wait for a fixed system mode.
                if UserDefaults.standard.bool(forKey: "AppleInterfaceStyleSwitchesAutomatically") {
                    status = .automatic
                    run = AppearanceRun()
                    return
                }
                if run.shouldApply(period, actualDark: actualDark) {
                    try await system.write(dark: period.dark)
                    let verified = try await system.read(askPermission: false)
                    guard !Task.isCancelled, generation == currentGeneration else { return }
                    guard verified == period.dark else {
                        throw AppearanceError(code: -1, message: "System appearance did not change")
                    }
                }
                status = run.manuallyOverridden ? .manualOverride : .scheduled(dark: period.dark)
            } catch is CancellationError {
                return
            } catch {
                guard generation == currentGeneration else { return }
                run = AppearanceRun()
                if let error = error as? AppearanceError,
                   error.code == errAEEventNotPermitted || error.code == errAEEventWouldRequireUserConsent {
                    status = .permission(code: error.code)
                } else {
                    status = .failed((error as? AppearanceError)?.message ?? error.localizedDescription)
                }
            }
        }
    }
}
