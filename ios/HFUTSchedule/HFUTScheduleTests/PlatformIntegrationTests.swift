import XCTest
@testable import HFUTSchedule

final class PlatformIntegrationTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        value.firstWeekday = 2
        return value
    }
    private func day(_ text: String) -> Date { PlatformScheduleResolver.date(text, calendar: calendar)! }
    private func course(weeks: [Int]? = nil, dates: [String]? = nil) -> Course {
        Course(name: "测试课程", teacher: "教师", location: "示例教室", weekday: 1,
            startTime: "08:00", endTime: "09:40", colorIndex: 0, weekIndices: weeks, dates: dates)
    }

    func testExplicitDatesAreAuthoritativeAndDeduplicated() {
        let value = course(weeks: [1, 3], dates: ["2026-11-03", "2026-11-03", "2026-02-30"])
        let items = PlatformScheduleResolver.occurrences(courses: [value], termStart: day("2026-09-07"), calendar: calendar)
        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(calendar.isDate(items[0].start, inSameDayAs: day("2026-11-03")))
        XCTAssertEqual(calendar.component(.hour, from: items[0].start), 8)
    }

    func testWeekIndicesExpandOnlySpecifiedWeeksAndSunday() {
        var value = course(weeks: [1, 3, 3, 0, 61])
        value.weekday = 7
        let items = PlatformScheduleResolver.occurrences(courses: [value], termStart: day("2026-09-07"), calendar: calendar)
        XCTAssertEqual(items.map { calendar.component(.day, from: $0.start) }, [13, 27])
    }

    func testUndatedCoursesNeedTermStartAndExplicitSemesterLength() {
        XCTAssertTrue(PlatformScheduleResolver.occurrences(courses: [course()], termStart: nil, calendar: calendar).isEmpty)
        XCTAssertEqual(PlatformScheduleResolver.occurrences(courses: [course()], termStart: day("2026-09-07"),
            semesterWeeks: 4, calendar: calendar).count, 4)
    }

    func testInvalidTimesAreSkippedAndMidnightEndWorks() {
        var value = course(dates: ["2026-11-03"])
        value.startTime = "25:00"
        XCTAssertTrue(PlatformScheduleResolver.occurrences(courses: [value], termStart: nil, calendar: calendar).isEmpty)
        value.startTime = "22:00"
        value.endTime = "24:00"
        let items = PlatformScheduleResolver.occurrences(courses: [value], termStart: nil, calendar: calendar)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].end.timeIntervalSince(items[0].start), 7200)
    }

    func testCalendarIdentitySurvivesTimeChangeForSameDay() {
        var value = course(dates: ["2026-11-03"])
        let first = PlatformScheduleResolver.occurrences(courses: [value], termStart: nil, calendar: calendar)[0]
        value.startTime = "08:30"
        let second = PlatformScheduleResolver.occurrences(courses: [value], termStart: nil, calendar: calendar)[0]
        XCTAssertEqual(first.id, second.id)
        XCTAssertNotEqual(first.start, second.start)
    }

    func testExamUsesActualDateAndDeadlineUsesEndForReminder() {
        let exam = AcademicExam(name: "测试考试", dateTime: "2026-11-03 14:00~16:00", place: "示例考场")
        let event = CustomEvent(title: "截止测试", start: day("2026-11-03"), end: day("2026-11-04"), kind: .deadline)
        let items = PlatformScheduleResolver.occurrences(courses: [], exams: [exam], events: [event], termStart: nil, calendar: calendar)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.first { $0.kind == .exam }?.location, "示例考场")
        let reminders = PlatformReminderPlanner.reminders(items, leadMinutes: 15, now: day("2026-11-02"))
        XCTAssertEqual(reminders.first { $0.occurrence.kind == .deadline }?.fireDate,
                       event.end.addingTimeInterval(-900))
    }

    func testReminderPlannerSelectsNearestFutureAndCapsBudget() {
        let items = PlatformScheduleResolver.occurrences(courses: [course()], termStart: day("2026-09-07"),
            semesterWeeks: 60, calendar: calendar)
        let reminders = PlatformReminderPlanner.reminders(Array(items.reversed()), leadMinutes: 15,
            now: day("2026-09-14"), limit: 3)
        XCTAssertEqual(reminders.count, 3)
        XCTAssertEqual(reminders[0].occurrence.start, items[1].start)
        XCTAssertEqual(PlatformReminderPlanner.reminders(items, leadMinutes: 15, now: day("2026-09-01"), limit: 100).count, 60)
        XCTAssertTrue(PlatformReminderPlanner.reminders(items, leadMinutes: 15, now: day("2026-09-01"), limit: 0).isEmpty)
    }

    func testRouteRoundTripAndRejectsMalformedRoutes() {
        let item = PlatformScheduleResolver.occurrences(courses: [course(dates: ["2026-11-03"])], termStart: nil, calendar: calendar)[0]
        let route = PlatformOccurrenceDestination(url: item.routeURL!)
        XCTAssertEqual(route?.sourceID, item.sourceID)
        XCTAssertEqual(route?.start, item.start)
        XCTAssertNil(PlatformOccurrenceDestination(url: URL(string: "https://occurrence?kind=course&id=wrong")!))
        XCTAssertNil(PlatformOccurrenceDestination(url: URL(string: "hfut-schedule://occurrence?kind=course&id=wrong")!))
    }
}
