import XCTest
@testable import HFUTSchedule

final class UpcomingExamTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        value.firstWeekday = 2
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

    private func exam(_ time: String, name: String = "高等数学", place: String = "教学楼 A201") -> AcademicExam {
        AcademicExam(name: name, dateTime: time, place: place)
    }

    func testParsesCanonicalUpstreamRangeWithoutGuessingDuration() throws {
        let value = exam("2026-11-18 08:00~10:00")
        let timing = try XCTUnwrap(UpcomingExamResolver.timing(for: value, calendar: calendar))
        XCTAssertEqual(timing.start, date("2026-11-18 08:00:00"))
        XCTAssertEqual(timing.end, date("2026-11-18 10:00:00"))
    }

    func testParsesChineseDateWeekdayFullWidthAndMeridiem() throws {
        let value = exam("2026年11月18日（周三）下午２点３０分至４点３０分")
        let timing = try XCTUnwrap(UpcomingExamResolver.timing(for: value, calendar: calendar))
        XCTAssertEqual(timing.start, date("2026-11-18 14:30:00"))
        XCTAssertEqual(timing.end, date("2026-11-18 16:30:00"))
        let noon = try XCTUnwrap(UpcomingExamResolver.timing(
            for: exam("2026/11/18 上午11:00—下午1:00"), calendar: calendar))
        XCTAssertEqual(noon.end, date("2026-11-18 13:00:00"))
    }

    func testAcademicHTMLParserAcceptsChineseExamTimesFromTable() throws {
        let html = """
        <table><tr><th>课程</th><th>考试时间</th><th>地点</th></tr>
        <tr><td>算法设计</td><td>2026年11月18日（周三）下午2时30分至4时30分</td><td>翡翠湖校区&nbsp;A201</td></tr>
        <tr><td>未安排课程</td><td>考试尚未安排</td><td>待定</td></tr></table>
        """
        let records = AcademicHTMLParser.exams(from: html)
        XCTAssertEqual(records.count, 1)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.name, "算法设计")
        XCTAssertEqual(record.place, "翡翠湖校区 A201")
        let timing = try XCTUnwrap(UpcomingExamResolver.timing(for: record, calendar: calendar))
        XCTAssertEqual(timing.start, date("2026-11-18 14:30:00"))
        XCTAssertEqual(timing.end, date("2026-11-18 16:30:00"))
    }

    func testRejectsMissingInvalidDatesTimesAndUnrelatedTimeLabels() {
        for value in ["", "考试尚未安排", "2026-02-30 08:00~10:00", "2026-11-18 24:00~25:00",
                      "2026-11-18 08:75~10:00", "2026-11-18 10:00~08:00",
                      "2026-11-18 08:00~08:00", "2026-11-18 08:00", "08:00~10:00",
                      "2026-11-18 报到08:00，考试09:00", "2026-11-18 上午11:00~1:00"] {
            XCTAssertNil(UpcomingExamResolver.timing(for: exam(value), calendar: calendar), value)
        }
    }

    func testFocusHasNo72HourThresholdAndExcludesPastExamDates() {
        let now = date("2026-11-14 08:00:00")
        let values = [exam("2026-11-13 08:00~10:00", name: "过去"),
                      exam("2026-11-14 09:00~11:00", name: "今天"),
                      exam("2026-12-18 08:00~10:00", name: "一个月后")]
        let result = UpcomingExamResolver.focusExams(values, now: now, calendar: calendar)
        XCTAssertEqual(result.map(\.exam.name), ["今天", "一个月后"])
    }

    func testFocusRetainsOngoingExamThroughEndingMinuteThenRemovesIt() {
        let values = [exam("2026-11-14 08:00~10:00")]
        XCTAssertEqual(UpcomingExamResolver.focusExams(values, now: date("2026-11-14 09:00:00"), calendar: calendar).count, 1)
        XCTAssertEqual(UpcomingExamResolver.focusExams(values, now: date("2026-11-14 10:00:59"), calendar: calendar).count, 1)
        XCTAssertTrue(UpcomingExamResolver.focusExams(values, now: date("2026-11-14 10:01:00"), calendar: calendar).isEmpty)
    }

    func testTimetableProjectsOnlySelectedWeekOnActualDateIncludingWeekend() throws {
        let values = [exam("2026-11-21 08:00~10:00"), exam("2026-11-23 08:00~10:00", name: "下周")]
        let result = UpcomingExamResolver.timetableCourses(values,
            inWeekStarting: date("2026-11-16 00:00:00"), calendar: calendar)
        let course = try XCTUnwrap(result.first)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(course.weekday, 6)
        XCTAssertEqual(course.dates, ["2026-11-21"])
        XCTAssertEqual(course.startTime, "08:00")
        XCTAssertEqual(course.endTime, "10:00")
        XCTAssertEqual(course.location, "教学楼 A201")
        XCTAssertEqual(course.source, "exam")
        XCTAssertEqual(course.details?.type, "考试")
    }

    func testHistoricalTimetableRemainsVisibleLikeUpstream() {
        let values = [exam("2026-10-13 08:00~10:00")]
        let result = UpcomingExamResolver.timetableCourses(values,
            inWeekStarting: date("2026-10-12 00:00:00"), calendar: calendar)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.weekday, 2)
    }

    func testDuplicateSourcesPreferLocationAndHaveStableCourseIDReverseLookup() throws {
        let values = [exam("2026-11-18 08:00~10:00", place: "暂无"),
                      exam("2026年11月18日 8:00至10:00", place: "  翡翠湖\n教学楼 A201  ")]
        let resolved = UpcomingExamResolver.resolved(values, calendar: calendar)
        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(resolved.first?.location, "翡翠湖 教学楼 A201")
        let monday = date("2026-11-16 00:00:00")
        let first = try XCTUnwrap(UpcomingExamResolver.timetableCourses(values, inWeekStarting: monday, calendar: calendar).first)
        let second = try XCTUnwrap(UpcomingExamResolver.timetableCourses(values.reversed(), inWeekStarting: monday, calendar: calendar).first)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(UpcomingExamResolver.exam(forCourseID: first.id, in: values, calendar: calendar)?.location,
                       "翡翠湖 教学楼 A201")
    }

    func testUnknownLocationGetsReadablePlaceholderAndInvalidRecordsAreSkipped() {
        let result = UpcomingExamResolver.resolved([
            exam("2026-11-18 08:00~10:00", place: "null"),
            exam("未安排"), exam("2026-11-18 08:00~10:00", name: " ")
        ], calendar: calendar)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.location, "地点待定")
    }

    func testOnlyExplicitEndDateCanProduceOvernightTimetableSegments() throws {
        let values = [exam("2026-11-18 23:00~2026-11-19 01:00")]
        let result = UpcomingExamResolver.timetableCourses(values,
            inWeekStarting: date("2026-11-16 00:00:00"), calendar: calendar)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.map(\.weekday), [3, 4])
        XCTAssertEqual(result.map(\.startTime), ["23:00", "00:00"])
        XCTAssertEqual(result.map(\.endTime), ["24:00", "01:00"])
        XCTAssertEqual(result.first?.id, result.last?.id)
        XCTAssertNil(UpcomingExamResolver.timing(for: exam("2026-11-18 23:00~01:00"), calendar: calendar))
    }
}
