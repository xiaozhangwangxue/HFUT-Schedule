import XCTest
@testable import HFUTSchedule

final class WidgetCalendarTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        value.firstWeekday = 2
        return value
    }

    private func date(_ value: String, calendar: Calendar? = nil) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar ?? self.calendar
        formatter.timeZone = formatter.calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: value)!
    }

    private func course(
        _ title: String = "测试课程", weekday: Int = 1,
        weeks: [Int]? = [1], dates: [String]? = ["2026-09-07"]
    ) -> WidgetCourseSnapshot {
        WidgetCourseSnapshot(id: UUID(), name: title, teacher: "", location: "测试教室", weekday: weekday,
            startTime: "08:00", endTime: "09:40", colorIndex: 0, weekIndices: weeks, dates: dates)
    }

    private func snapshot(_ courses: [WidgetCourseSnapshot], termStart: Date? = nil) -> WidgetScheduleSnapshot {
        WidgetScheduleSnapshot(revision: UUID(), updatedAt: date("2026-11-14 12:00"), termStart: termStart, courses: courses)
    }

    func testExplicitSemesterStartOverridesDatesFromOlderCourseData() {
        let saved = snapshot([course(weeks: [3])], termStart: date("2026-11-02 12:00"))
        let result = WidgetScheduleCalendar.project(saved, on: date("2026-11-16 10:00"), calendar: calendar)
        XCTAssertEqual(result.week, 3)
        XCTAssertEqual(result.monday, date("2026-11-16 00:00"))
        XCTAssertEqual(result.courses.count, 1)
    }

    func testLegacySemesterInferenceUsesMajorityRatherThanFirstOldCourse() {
        let old = course("旧学期", dates: ["2026-02-23"])
        let current = [course("当前课程甲"), course("当前课程乙", weekday: 2, dates: ["2026-09-08"])]
        let saved = snapshot([old] + current)
        XCTAssertEqual(WidgetScheduleCalendar.termStart(from: saved, calendar: calendar), date("2026-09-07 00:00"))
        let result = WidgetScheduleCalendar.project(saved, on: date("2026-11-16 00:00"), calendar: calendar)
        XCTAssertEqual(result.week, 11)
        XCTAssertEqual(result.monday, date("2026-11-16 00:00"))
    }

    func testSemesterVoteTiePrefersNewerSemesterAndIgnoresInputOrder() {
        let old = course("旧学期", dates: ["2026-02-23"])
        let recent = course("新学期", dates: ["2026-09-07"])
        XCTAssertEqual(WidgetScheduleCalendar.derivedTermStart(from: [old, recent], calendar: calendar), date("2026-09-07 00:00"))
        XCTAssertEqual(WidgetScheduleCalendar.derivedTermStart(from: [recent, old], calendar: calendar), date("2026-09-07 00:00"))
    }

    func testInvalidLegacyDatesWeekdaysAndWeekIndicesCannotDetermineSemester() {
        let invalid = [course("非法日期", dates: ["2026-02-30"]),
                       course("非法星期", weekday: 9), course("非法周次", weeks: [-1, 0])]
        XCTAssertNil(WidgetScheduleCalendar.derivedTermStart(from: invalid, calendar: calendar))
        let result = WidgetScheduleCalendar.project(nil, on: date("2026-11-14 12:00"), calendar: calendar)
        XCTAssertEqual(result.week, 1)
        XCTAssertEqual(result.monday, date("2026-11-09 00:00"))
    }

    func testInjectedDateChangesWeekExactlyAtLocalMondayMidnight() {
        let start = date("2026-11-02 00:00")
        XCTAssertEqual(WidgetScheduleCalendar.currentWeek(termStart: start, on: date("2026-11-08 23:59"), calendar: calendar), 1)
        XCTAssertEqual(WidgetScheduleCalendar.currentWeek(termStart: start, on: date("2026-11-09 00:00"), calendar: calendar), 2)
        XCTAssertEqual(WidgetScheduleCalendar.currentWeek(termStart: start, on: date("2026-11-01 23:59"), calendar: calendar), 1)
    }

    func testSemesterWeekDoesNotRepeatWeekTwentyAfterSemesterEnds() throws {
        let start = date("2026-09-07 00:00")
        let later = try XCTUnwrap(calendar.date(byAdding: .day, value: 21 * 7, to: start))
        let result = WidgetScheduleCalendar.project(snapshot([course(weeks: [20])], termStart: start), on: later, calendar: calendar)
        XCTAssertEqual(result.week, 22)
        XCTAssertTrue(result.courses.isEmpty)
    }

    func testVisibleWeekFiltersInactiveAndWeekendCoursesAndDeduplicatesSlots() {
        let first = course("周一课程", weeks: [1, 3])
        var duplicate = first
        duplicate.id = UUID()
        let records = [first, duplicate, course("其他周", weeks: [2]),
                       course("周六", weekday: 6), course("周日", weekday: 7), course("无效星期", weekday: 0)]
        XCTAssertEqual(WidgetScheduleCalendar.courses(records, in: 1), [first])
        XCTAssertEqual(WidgetScheduleCalendar.courses(records, in: 2).map(\.name), ["其他周"])
    }

    func testManualCoursesWithoutWeekMetadataRemainVisible() {
        let manual = course("手动课程", weeks: nil, dates: nil)
        XCTAssertEqual(WidgetScheduleCalendar.courses([manual], in: 27), [manual])
    }

    func testReceivedScheduleWithEmptyCurrentWeekIsNotMissingData() {
        let now = date("2026-11-02 12:00")
        let result = WidgetScheduleCalendar.project(snapshot([course(weeks: [2])], termStart: date("2026-11-02 00:00")),
                                                    on: now, calendar: calendar)
        XCTAssertTrue(result.courses.isEmpty)
        let data = WeeklyScheduleViewData(date: now, week: result.week, monday: result.monday,
                                          courses: result.courses, hasScheduleData: true, calendar: calendar)
        XCTAssertEqual(data.emptyStateTitle, "本周没有课程")
        XCTAssertFalse(data.emptyStateMessage.contains("同步一次"))
    }

    func testAuthoritativeEmptyScheduleAndMissingSnapshotUseDifferentMessages() {
        let now = date("2026-11-14 12:00")
        let validEmpty = WeeklyScheduleViewData(date: now, week: 1, monday: nil, courses: [], hasScheduleData: true)
        let missing = WeeklyScheduleViewData(date: now, week: 1, monday: nil, courses: [], hasScheduleData: false)
        XCTAssertEqual(validEmpty.emptyStateTitle, "本周没有课程")
        XCTAssertEqual(missing.emptyStateTitle, "还没有课表数据")
        XCTAssertTrue(missing.emptyStateMessage.contains("打开 App 同步"))
    }

    func testRefreshUsesDataPresenceRatherThanWhetherCurrentWeekIsEmpty() {
        let now = date("2026-11-14 12:00")
        XCTAssertEqual(WidgetScheduleCalendar.nextRefresh(after: now, hasScheduleData: true, calendar: calendar), date("2026-11-14 12:30"))
        XCTAssertEqual(WidgetScheduleCalendar.nextRefresh(after: now, hasScheduleData: false, calendar: calendar), date("2026-11-14 12:15"))
        XCTAssertEqual(WidgetScheduleCalendar.nextRefresh(after: date("2026-11-14 23:59"), calendar: calendar), date("2026-11-15 00:01"))
    }

    func testWeekArithmeticUsesCalendarDaysAcrossDaylightSavingBoundary() {
        var pacific = Calendar(identifier: .gregorian)
        pacific.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let start = date("2026-03-02 00:00", calendar: pacific)
        let followingMonday = date("2026-03-09 00:00", calendar: pacific)
        XCTAssertEqual(WidgetScheduleCalendar.currentWeek(termStart: start, on: followingMonday, calendar: pacific), 2)
    }
}
