import XCTest
@testable import HFUTSchedule

final class CampusBusUpgradeTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }

    private func date(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: value)!
    }

    private func route(_ time: String, week: String = "周六", from: String = "翡翠湖", to: String = "屯溪路") -> CampusBusRoute {
        CampusBusRoute(week: week, time: time, from: from, to: to,
                       place: "校门", count: 1, stops: [])
    }

    func testParserPreservesWeekRowspanHiddenCellsAndNormalizesDeparture() throws {
        // Same six visible data columns and inherited weekday cell as the university HTML.
        let html = """
        <table class="docx_4"><tr><th>星期</th><th>运行区间</th></tr>
        <tr><td rowspan="2">周一至周五</td><td>翡翠湖 — 屯溪路</td><td>7:5</td>
        <td>校门</td><td>南区<br>北区</td><td>2</td><td>备注</td><td style="display:none">忽略</td></tr>
        <tr><td>屯溪路—翡翠湖</td><td>17:30</td><td>东门</td><td>南区</td><td>1</td><td></td></tr>
        <tr><td rowspan="1">周六</td><td>翡翠湖—屯溪路</td><td>08:00</td><td>校门</td><td></td><td>1</td><td></td></tr>
        <tr><td>翡翠湖—屯溪路</td><td>26:00</td><td>校门</td><td></td><td>1</td><td></td></tr></table>
        """
        let routes = CampusBusService.parse(html)
        XCTAssertEqual(routes.count, 3)
        let first = try XCTUnwrap(routes.first)
        XCTAssertEqual(first.week, "周一至周五")
        XCTAssertEqual(first.time, "07:05")
        XCTAssertEqual(first.from, "翡翠湖")
        XCTAssertEqual(first.to, "屯溪路")
        XCTAssertEqual(first.count, 2)
        XCTAssertEqual(first.points, ["翡翠湖", "南区", "北区", "屯溪路"])
        XCTAssertEqual(routes[1].week, "周一至周五")
        XCTAssertEqual(routes[2].week, "周六")
    }

    func testParserFallsBackToTableContainingRouteHeader() {
        let html = """
        <table><tr><th>运行区间</th></tr><tr><td rowspan="1">周日</td>
        <td>宣城—合肥</td><td>9:00</td><td>南门</td><td></td><td>1</td><td></td></tr></table>
        """
        XCTAssertEqual(CampusBusService.parse(html).first?.time, "09:00")
        XCTAssertTrue(CampusBusService.parse("<html>没有班车表格</html>").isEmpty)
    }

    func testTodayRemovesDepartingMinuteAndEarlierTripsImmediately() {
        let now = date("2026-11-14 08:00:00")
        let result = CampusBusService.select(
            [route("09:00"), route("07:59"), route("08:01"), route("08:00")],
            mode: .upcoming, date: now, now: now, calendar: calendar
        )
        XCTAssertEqual(result.routes.map(\.time), ["08:01", "09:00"])
        XCTAssertTrue(result.hasDepartedTrips)
        let lastMinute = CampusBusService.select(result.routes, mode: .upcoming,
            date: now, now: date("2026-11-14 09:00:00"), calendar: calendar)
        XCTAssertTrue(lastMinute.routes.isEmpty)
        XCTAssertEqual(lastMinute.emptyMessage, "今天的运营已结束")
    }

    func testFutureDateKeepsMorningRoutesAndFiltersByNaturalWeekday() {
        let now = date("2026-11-14 21:00:00")
        let result = CampusBusService.select(
            [route("08:00"), route("07:00", week: "周日"), route("06:00", week: "周一至周五")],
            mode: .upcoming, date: date("2026-11-15 00:00:00"), now: now, calendar: calendar
        )
        XCTAssertEqual(result.routes.map(\.time), ["07:00"])
        XCTAssertFalse(result.hasDepartedTrips)
        XCTAssertEqual(CampusBusService.weekdayGroup(for: date("2026-11-16 00:00:00"), calendar: calendar), "周一至周五")
    }

    func testAllArrangementsRetainDepartedTripsAcrossWeekGroupsAndFilterDirection() {
        let now = date("2026-11-14 21:00:00")
        let routes = [route("08:00"), route("07:00", week: "周日"), route("09:00", from: "屯溪路", to: "翡翠湖")]
        let outgoing = CampusBusService.select(routes, mode: .all, date: now, now: now,
            from: "翡翠湖", to: "屯溪路", calendar: calendar)
        XCTAssertEqual(outgoing.routes.map(\.time), ["07:00", "08:00"])
        let returning = CampusBusService.select(routes, mode: .all, date: now, now: now,
            from: "屯溪路", to: "翡翠湖", calendar: calendar)
        XCTAssertEqual(returning.routes.map(\.time), ["09:00"])
        XCTAssertFalse(outgoing.hasDepartedTrips)
    }

    func testMinuteRefreshAlignsToBoundary() {
        XCTAssertEqual(CampusBusService.secondsUntilNextMinute(from: date("2026-11-14 08:00:00")), 60)
        XCTAssertEqual(CampusBusService.secondsUntilNextMinute(from: date("2026-11-14 08:00:59")), 1)
        let fractional = date("2026-11-14 08:00:59").addingTimeInterval(0.75)
        XCTAssertEqual(CampusBusService.secondsUntilNextMinute(from: fractional), 0.25, accuracy: 0.001)
    }

    func testHolidayAndMakeupNoticeDoesNotReplaceNaturalWeekdayRoutes() {
        XCTAssertNil(CampusBusService.holidayAdvisory(for: nil))
        XCTAssertTrue(CampusBusService.holidayAdvisory(for:
            HolidayDay(name: "国庆节", date: "2026-10-01", isOffDay: true))!.contains("假期"))
        XCTAssertTrue(CampusBusService.holidayAdvisory(for:
            HolidayDay(name: "国庆节", date: "2026-10-10", isOffDay: false))!.contains("调休工作日"))
        let makeupSaturday = date("2026-10-10 00:00:00")
        let result = CampusBusService.select([route("08:00"), route("09:00", week: "周一至周五")],
            mode: .upcoming, date: makeupSaturday, now: makeupSaturday, calendar: calendar)
        XCTAssertEqual(result.routes.map(\.time), ["08:00"])
    }
}
