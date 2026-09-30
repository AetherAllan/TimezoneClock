import Foundation

@main
struct ClockChecks {
    static func main() throws {
        let iso = ISO8601DateFormatter()
        func instant(_ value: String) throws -> Date {
            guard let date = iso.date(from: value) else { throw CheckError.invalidDate }
            return date
        }
        func zone(_ id: String) throws -> ClockZone {
            guard let zone = ClockZone(id) else { throw CheckError.invalidZone }
            return zone
        }

        let beijing = try zone("Asia/Shanghai")
        let losAngeles = try zone("America/Los_Angeles")
        let winter = try instant("2026-01-15T00:00:00Z")
        let summer = try instant("2026-07-02T00:00:00Z")
        assert(beijing.time(at: winter) == "08:00")
        assert(beijing.time(at: summer) == "08:00")
        assert(losAngeles.time(at: winter) == "16:00")
        assert(losAngeles.day(at: winter) == "2026/01/14")
        assert(losAngeles.offset(at: winter) == "UTC−08:00")
        assert(losAngeles.time(at: summer) == "17:00")
        assert(losAngeles.day(at: summer) == "2026/07/01")
        assert(losAngeles.offset(at: summer) == "UTC−07:00")
        let beijingMidnight = try instant("2026-07-01T16:00:00Z")
        let beforeDST = try instant("2026-03-08T09:59:00Z")
        let afterDST = try instant("2026-03-08T10:00:00Z")
        let kathmandu = try zone("Asia/Kathmandu")
        assert(beijing.day(at: beijingMidnight) == "2026/07/02")
        assert(losAngeles.time(at: beforeDST) == "01:59")
        assert(losAngeles.time(at: afterDST) == "03:00")
        assert(kathmandu.offset(at: winter) == "UTC+05:45")

        let previousDefault = NSTimeZone.default
        NSTimeZone.default = losAngeles.timeZone
        assert(beijing.time(at: winter) == "08:00")
        NSTimeZone.default = previousDefault
        assert(beijing.matches("北京") && beijing.matches("Shanghai"))
        assert(losAngeles.matches("los angeles") && losAngeles.matches("America/Los_Angeles"))
        assert(!ClockZone.available.isEmpty)
        assert(ClockZone("invalid/zone") == nil)

        var selection = ClockSelection(identifiers: ["invalid/zone", "Asia/Shanghai", "Asia/Shanghai"])
        assert(selection.identifiers == ["Asia/Shanghai"])
        selection.remove("Asia/Shanghai")
        assert(selection.identifiers == ["Asia/Shanghai"])
        selection.add("America/Los_Angeles")
        selection.add("America/Los_Angeles")
        selection.add("invalid/zone")
        assert(selection.identifiers.count == 2)
        selection.pin("America/Los_Angeles")
        selection.pin("Asia/Tokyo")
        assert(selection.primary == "America/Los_Angeles")
        selection.remove("America/Los_Angeles")
        assert(selection.primary == "Asia/Shanghai")
        assert(ClockSelection(identifiers: []).identifiers == ClockZone.defaultIdentifiers)

        assert(beijing.time(at: winter, seconds: true) == "08:00:00")
        let withSeconds = try instant("2026-01-15T16:00:59Z")
        assert(beijing.time(at: withSeconds, seconds: true) == "00:00:59")
        assert(beijing.name(language: .english) == "Beijing")
        assert(losAngeles.name(language: .traditionalChinese) == "洛杉磯")
        assert(losAngeles.matches("洛杉磯", language: .traditionalChinese))
        let keys = try AppLanguage.allCases.filter { $0 != .system }.map { language -> Set<String> in
            guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj") else {
                throw CheckError.invalidResources
            }
            let data = try Data(contentsOf: URL(fileURLWithPath: path).appendingPathComponent("Localizable.strings"))
            guard let values = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String],
                  values.values.allSatisfy({ !$0.isEmpty }) else { throw CheckError.invalidResources }
            return Set(values.keys)
        }
        assert(keys.count == 3 && keys.allSatisfy { $0 == keys[0] } && keys[0].count > 40)

        var schedule = AppearanceSchedule()
        let morning = try instant("2026-01-14T23:00:00Z") // Beijing 07:00
        let beforeMorning = morning.addingTimeInterval(-1)
        let evening = try instant("2026-01-15T11:00:00Z") // Beijing 19:00
        assert(schedule.period(at: beforeMorning)?.dark == true)
        assert(schedule.period(at: morning)?.dark == false)
        assert(schedule.period(at: evening)?.dark == true)
        assert(schedule.period(at: evening)?.start == evening)
        schedule.timeZoneID = "America/Los_Angeles"
        let winterMorning = try instant("2026-01-15T15:00:00Z")
        let summerMorning = try instant("2026-07-02T14:00:00Z")
        assert(schedule.period(at: winterMorning)?.start == winterMorning)
        assert(schedule.period(at: summerMorning)?.start == summerMorning)
        schedule.lightMinute = 22 * 60
        schedule.darkMinute = 6 * 60
        assert(schedule.period(at: winter)?.dark == true) // LA 16:00
        let overnight = try instant("2026-01-15T08:00:00Z") // LA midnight
        assert(schedule.period(at: overnight)?.dark == false)
        schedule.lightMinute = 2 * 60 + 30
        schedule.darkMinute = 19 * 60
        assert(schedule.period(at: beforeDST)?.dark == true)
        assert(schedule.period(at: afterDST)?.dark == false) // Missing 02:30 advances to 03:00
        assert(schedule.period(at: afterDST)?.start == afterDST)
        schedule.lightMinute = 130
        schedule.darkMinute = 140
        assert(schedule.period(at: afterDST)?.dark == true) // Both missing times advance to 03:00
        schedule.lightMinute = 140
        schedule.darkMinute = 130
        assert(schedule.period(at: afterDST)?.dark == false) // Later wall time wins
        schedule.lightMinute = 90
        schedule.darkMinute = 19 * 60
        let firstRepeated = try instant("2026-11-01T08:30:00Z")
        let secondRepeated = try instant("2026-11-01T09:30:00Z")
        assert(schedule.period(at: firstRepeated)?.start == firstRepeated)
        assert(schedule.period(at: secondRepeated)?.start == firstRepeated)
        schedule.darkMinute = 90
        assert(!schedule.isValid && schedule.period(at: winter) == nil)

        var run = AppearanceRun()
        let light = AppearancePeriod(start: morning, dark: false)
        let dark = AppearancePeriod(start: evening, dark: true)
        assert(run.shouldApply(light, actualDark: true))
        assert(!run.shouldApply(light, actualDark: false) && !run.manuallyOverridden)
        assert(!run.shouldApply(light, actualDark: true) && run.manuallyOverridden)
        assert(!run.shouldApply(light, actualDark: false) && run.manuallyOverridden)
        assert(run.shouldApply(dark, actualDark: false) && !run.manuallyOverridden)
        let tomorrowDark = AppearancePeriod(start: evening.addingTimeInterval(86400), dark: true)
        assert(run.shouldApply(tomorrowDark, actualDark: false)) // Waking next day resets the override

        var preferences = ClockPreferences()
        preferences.language = .traditionalChinese
        preferences.showDate = true
        preferences.showSeconds = true
        preferences.schedule.timeZoneID = "Asia/Tokyo"
        let saved = try JSONEncoder().encode(preferences)
        assert(ClockPreferences.load(from: saved) == preferences)
        preferences.schedule.timeZoneID = "invalid/zone"
        preferences.schedule.enabled = true
        let invalid = try JSONEncoder().encode(preferences)
        assert(ClockPreferences.load(from: invalid).schedule == AppearanceSchedule())
        assert(ClockPreferences.load(from: Data("invalid".utf8)) == ClockPreferences())

        print("PASS: 时间换算、日期秒数、三种语言资源、选择规则、跨日与夏令时调度、手动覆盖、配置恢复")
    }

    enum CheckError: Error { case invalidDate, invalidZone, invalidResources }
}
