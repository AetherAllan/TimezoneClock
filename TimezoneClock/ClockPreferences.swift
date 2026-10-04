import Foundation

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system, simplifiedChinese = "zh-Hans", traditionalChinese = "zh-Hant", english = "en"
    var id: String { rawValue }

    var resolved: AppLanguage {
        guard self == .system else { return self }
        for preferred in Locale.preferredLanguages {
            if preferred.hasPrefix("zh") {
                return preferred.contains("Hant") || preferred.contains("TW") || preferred.contains("HK")
                    ? .traditionalChinese : .simplifiedChinese
            }
            if preferred.hasPrefix("en") { return .english }
        }
        return .english
    }

    var locale: Locale { Locale(identifier: resolved.rawValue) }
    var title: String {
        switch self {
        case .system: text("Follow System")
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .english: "English"
        }
    }

    func text(_ key: String, bundle: Bundle = .main) -> String {
        guard let path = bundle.path(forResource: resolved.rawValue, ofType: "lproj"),
              let localizedBundle = Bundle(path: path) else { return key }
        return localizedBundle.localizedString(forKey: key, value: key, table: nil)
    }
}

enum InterfaceStyle: String, Codable, CaseIterable, Identifiable {
    case liquidGlass, standard
    var id: String { rawValue }
}

struct ClockPreferences: Codable, Equatable {
    var language: AppLanguage = .simplifiedChinese
    var showDate = false
    var showSeconds = false
    var interfaceStyle: InterfaceStyle = .liquidGlass
    var schedule = AppearanceSchedule()

    private enum CodingKeys: String, CodingKey {
        case language, showDate, showSeconds, interfaceStyle, schedule
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        language = try values.decode(AppLanguage.self, forKey: .language)
        showDate = try values.decode(Bool.self, forKey: .showDate)
        showSeconds = try values.decode(Bool.self, forKey: .showSeconds)
        schedule = try values.decode(AppearanceSchedule.self, forKey: .schedule)
        // Older versions lack this key; an unrecognized style must not reset other preferences.
        let style = try values.decodeIfPresent(String.self, forKey: .interfaceStyle)
        interfaceStyle = style.flatMap(InterfaceStyle.init(rawValue:)) ?? .liquidGlass
    }

    var refreshInterval: TimeInterval { showSeconds ? 1 : 60 }

    func nextRefresh(after date: Date) -> Date {
        Date(timeIntervalSince1970: (floor(date.timeIntervalSince1970 / refreshInterval) + 1) * refreshInterval)
    }

    static func load(from data: Data?) -> ClockPreferences {
        guard let data, var value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        if !value.schedule.isValid { value.schedule = AppearanceSchedule() }
        return value
    }
}

struct AppearanceSchedule: Codable, Equatable {
    var enabled = false
    var timeZoneID = "Asia/Shanghai"
    var lightMinute = 7 * 60
    var darkMinute = 19 * 60

    var isValid: Bool {
        TimeZone(identifier: timeZoneID) != nil && (0..<1440).contains(lightMinute)
            && (0..<1440).contains(darkMinute) && lightMinute != darkMinute
    }

    // Resolve real instants in the chosen zone. Missing DST times move to the next valid time;
    // repeated times use their first occurrence, so each daily transition runs once.
    func period(at now: Date) -> AppearancePeriod? {
        guard isValid, let zone = TimeZone(identifier: timeZoneID) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return nil }
        var periods: [(period: AppearancePeriod, minute: Int)] = []
        for day in [yesterday, today] {
            for (minute, dark) in [(lightMinute, false), (darkMinute, true)] {
                if let date = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0,
                                           of: day, matchingPolicy: .nextTime, repeatedTimePolicy: .first),
                   date <= now {
                    periods.append((AppearancePeriod(start: date, dark: dark), minute))
                }
            }
        }
        // Two missing DST times can both advance to the same instant; the later wall time wins.
        return periods.max {
            $0.period.start == $1.period.start ? $0.minute < $1.minute : $0.period.start < $1.period.start
        }?.period
    }
}

struct AppearancePeriod: Equatable {
    let start: Date
    let dark: Bool
}

struct AppearanceRun {
    private(set) var period: AppearancePeriod?
    private(set) var manuallyOverridden = false

    // Use the period at successful completion, since permission requests can cross a boundary.
    mutating func recordManualOverride(_ period: AppearancePeriod) {
        self.period = period
        manuallyOverridden = true
    }

    mutating func shouldApply(_ next: AppearancePeriod, actualDark: Bool) -> Bool {
        if period != next {
            period = next
            manuallyOverridden = false
            return actualDark != next.dark
        }
        if actualDark != next.dark { manuallyOverridden = true }
        return false
    }
}
