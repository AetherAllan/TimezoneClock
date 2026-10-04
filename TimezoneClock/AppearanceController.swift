import AppKit
import Carbon
import Observation

enum AppearanceStatus {
    case off, checking, switching, automatic, manualAutomatic, manualOverride, invalidSchedule
    case scheduled(dark: Bool)
    case changed(dark: Bool)
    case permission(code: Int32)
    case failed(String)

    func text(language: AppLanguage) -> String {
        switch self {
        case .off: language.text("Scheduling is off")
        case .checking: language.text("Checking system appearance…")
        case .switching: language.text("Switching system appearance…")
        case .automatic: language.text("Choose Light or Dark in macOS Appearance to let this schedule take over.")
        case .manualAutomatic: language.text("Choose Light or Dark in macOS Appearance before using this control.")
        case .manualOverride: language.text("Manual appearance change kept until the next scheduled transition.")
        case .invalidSchedule: language.text("Light and dark times must be different.")
        case .scheduled(let dark): language.text(dark ? "Scheduled appearance: Dark" : "Scheduled appearance: Light")
        case .changed(let dark): language.text(dark ? "System appearance: Dark" : "System appearance: Light")
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
        try Task.checkCancellation()
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
    private(set) var actualDark: Bool?
    private(set) var manualStatus: AppearanceStatus?
    var isBusy: Bool { task != nil }
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
        manualStatus = nil
        status = schedule.enabled ? .checking : .off
        tick(at: Date(), force: true, askPermission: askPermission)
    }

    // Refreshes are read-only, including when the schedule is disabled. Permission is requested
    // only by an explicit action, so opening settings never raises an automation prompt.
    func refreshActualAppearance() {
        guard task == nil else { return }
        let currentGeneration = generation
        manualStatus = .checking
        task = Task { [weak self] in
            guard let self else { return }
            defer { finishOperation(generation: currentGeneration) }
            do {
                try ensureCurrentGeneration(currentGeneration)
                try await prepareSystemEvents()
                try ensureCurrentGeneration(currentGeneration)
                let actual = try await system.read(askPermission: false)
                try ensureCurrentGeneration(currentGeneration)
                actualDark = actual
                manualStatus = usesAutomaticAppearance ? .manualAutomatic : nil
            } catch is CancellationError {
                return
            } catch {
                guard generation == currentGeneration else { return }
                actualDark = nil
                manualStatus = errorStatus(error)
            }
        }
    }

    func setAppearanceManually(dark: Bool) {
        guard task == nil else { return }
        let currentGeneration = generation
        manualStatus = .switching
        task = Task { [weak self] in
            guard let self else { return }
            defer { finishOperation(generation: currentGeneration) }
            do {
                try ensureCurrentGeneration(currentGeneration)
                try await prepareSystemEvents()
                try ensureCurrentGeneration(currentGeneration)
                let actual = try await system.read(askPermission: true)
                try ensureCurrentGeneration(currentGeneration)
                actualDark = actual
                guard !usesAutomaticAppearance else {
                    manualStatus = .manualAutomatic
                    return
                }
                if actual != dark {
                    try await system.write(dark: dark)
                    let verified = try await system.read(askPermission: false)
                    try ensureCurrentGeneration(currentGeneration)
                    guard verified == dark else {
                        throw AppearanceError(code: -1, message: "System appearance did not change")
                    }
                }
                actualDark = dark
                manualStatus = .changed(dark: dark)
                // Permission prompts can cross a transition. The successful write belongs to
                // the period at completion, not the period when the user clicked the control.
                if schedule.enabled, let period = schedule.period(at: Date()) {
                    run.recordManualOverride(period)
                    status = .manualOverride
                }
            } catch is CancellationError {
                return
            } catch {
                guard generation == currentGeneration else { return }
                actualDark = nil
                manualStatus = errorStatus(error)
            }
        }
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
            defer { finishOperation(generation: currentGeneration) }
            do {
                try ensureCurrentGeneration(currentGeneration)
                try await prepareSystemEvents()
                try ensureCurrentGeneration(currentGeneration)
                let actual = try await system.read(askPermission: askPermission)
                try ensureCurrentGeneration(currentGeneration)
                actualDark = actual
                manualStatus = nil
                // Request access even while macOS Auto is enabled, so the app can appear in
                // Automation settings. Only appearance writes wait for a fixed system mode.
                if usesAutomaticAppearance {
                    status = .automatic
                    run = AppearanceRun()
                    return
                }
                if run.shouldApply(period, actualDark: actual) {
                    try await system.write(dark: period.dark)
                    let verified = try await system.read(askPermission: false)
                    try ensureCurrentGeneration(currentGeneration)
                    guard verified == period.dark else {
                        throw AppearanceError(code: -1, message: "System appearance did not change")
                    }
                    actualDark = verified
                }
                status = run.manuallyOverridden ? .manualOverride : .scheduled(dark: period.dark)
            } catch is CancellationError {
                return
            } catch {
                guard generation == currentGeneration else { return }
                run = AppearanceRun()
                actualDark = nil
                status = errorStatus(error)
            }
        }
    }

    private var usesAutomaticAppearance: Bool {
        UserDefaults.standard.bool(forKey: "AppleInterfaceStyleSwitchesAutomatically")
    }

    private func ensureCurrentGeneration(_ expected: Int) throws {
        try Task.checkCancellation()
        guard generation == expected else { throw CancellationError() }
    }

    private func finishOperation(generation completedGeneration: Int) {
        if generation == completedGeneration { task = nil }
    }

    // Permission preflight requires a running target. Launch the system helper quietly.
    private func prepareSystemEvents() async throws {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systemevents").isEmpty else { return }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systemevents") else {
            throw AppearanceError(code: Int32(procNotFound), message: "System Events is unavailable")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    private func errorStatus(_ error: Error) -> AppearanceStatus {
        if let error = error as? AppearanceError,
           error.code == errAEEventNotPermitted || error.code == errAEEventWouldRequireUserConsent {
            return .permission(code: error.code)
        }
        return .failed((error as? AppearanceError)?.message ?? error.localizedDescription)
    }
}
