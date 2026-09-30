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

        print("PASS: 北京时间、冬夏令时、夏令时跳转、跨日、45 分钟偏移、系统时区独立、搜索与选择规则")
    }

    enum CheckError: Error { case invalidDate, invalidZone }
}
