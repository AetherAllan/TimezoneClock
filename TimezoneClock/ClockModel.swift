import Foundation

struct ClockZone: Identifiable {
    let id: String
    let timeZone: TimeZone

    init?(_ identifier: String) {
        guard let timeZone = TimeZone(identifier: identifier) else { return nil }
        id = identifier
        self.timeZone = timeZone
    }

    static let defaultIdentifiers = [
        "Asia/Shanghai", "America/Los_Angeles", "America/New_York",
        "Europe/London", "Asia/Tokyo"
    ]

    static let available = TimeZone.knownTimeZoneIdentifiers.compactMap(ClockZone.init)
        .sorted { $0.id < $1.id }

    var name: String {
        switch id {
        case "Asia/Shanghai": "北京"
        case "America/Los_Angeles": "洛杉矶"
        case "America/New_York": "纽约"
        case "Europe/London": "伦敦"
        case "Asia/Tokyo": "东京"
        default: (id.split(separator: "/").last.map(String.init) ?? id)
                .replacingOccurrences(of: "_", with: " ")
        }
    }

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let localizedName = timeZone.localizedName(for: .generic, locale: Locale(identifier: "zh_CN")) ?? ""
        return query.isEmpty || name.localizedStandardContains(query)
            || id.localizedStandardContains(query)
            || id.replacingOccurrences(of: "_", with: " ").localizedStandardContains(query)
            || localizedName.localizedStandardContains(query)
    }

    func time(at date: Date) -> String {
        date.formatted(.verbatim(
            "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
            timeZone: timeZone, calendar: Calendar(identifier: .gregorian)
        ))
    }

    func day(at date: Date) -> String {
        date.formatted(Date.FormatStyle(
            locale: Locale(identifier: "zh_CN"),
            calendar: Calendar(identifier: .gregorian), timeZone: timeZone
        ).year().month(.twoDigits).day(.twoDigits))
    }

    func offset(at date: Date) -> String {
        let seconds = timeZone.secondsFromGMT(for: date)
        let minutes = abs(seconds) / 60
        return String(format: "UTC%@%02d:%02d", seconds < 0 ? "−" : "+", minutes / 60, minutes % 60)
    }
}

struct ClockSelection {
    private(set) var identifiers: [String]
    private(set) var primary: String

    init(identifiers: [String] = ClockZone.defaultIdentifiers, primary: String = "Asia/Shanghai") {
        var seen = Set<String>()
        let valid = identifiers.filter { ClockZone($0) != nil && seen.insert($0).inserted }
        self.identifiers = valid.isEmpty ? ClockZone.defaultIdentifiers : valid
        self.primary = self.identifiers.contains(primary)
            ? primary : (self.identifiers.first ?? "Asia/Shanghai")
    }

    var zones: [ClockZone] { identifiers.compactMap(ClockZone.init) }

    mutating func add(_ identifier: String) {
        guard ClockZone(identifier) != nil, !identifiers.contains(identifier) else { return }
        identifiers.append(identifier)
    }

    mutating func remove(_ identifier: String) {
        guard identifiers.count > 1 else { return }
        identifiers.removeAll { $0 == identifier }
        if primary == identifier, let first = identifiers.first { primary = first }
    }

    mutating func pin(_ identifier: String) {
        guard identifiers.contains(identifier) else { return }
        primary = identifier
    }
}
