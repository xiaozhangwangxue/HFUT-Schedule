import Foundation

struct WidgetScheduleWeek: Equatable {
    let week: Int
    let monday: Date
    let courses: [WidgetCourseSnapshot]
}

/// Date calculations shared by the WidgetKit provider and deterministic tests.
/// A snapshot's explicit semester start is authoritative, including a date the
/// user selected in the app. Legacy arrays infer it by voting across courses.
enum WidgetScheduleCalendar {
    static func gregorian(_ source: Calendar = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = source.timeZone
        calendar.firstWeekday = 2
        return calendar
    }

    static func project(
        _ snapshot: WidgetScheduleSnapshot?, on date: Date = .now,
        calendar source: Calendar = .current
    ) -> WidgetScheduleWeek {
        let calendar = gregorian(source)
        let semesterStart = snapshot.flatMap { termStart(from: $0, calendar: calendar) }
        let week = currentWeek(termStart: semesterStart, on: date, calendar: calendar)
        let monday = semesterStart.flatMap {
            calendar.date(byAdding: .day, value: (week - 1) * 7, to: $0)
        } ?? calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        return WidgetScheduleWeek(week: week, monday: monday,
                                  courses: courses(snapshot?.courses ?? [], in: week))
    }

    static func termStart(from snapshot: WidgetScheduleSnapshot, calendar source: Calendar = .current) -> Date? {
        let calendar = gregorian(source)
        if let explicit = snapshot.termStart, explicit.timeIntervalSince1970.isFinite {
            return calendar.startOfDay(for: explicit)
        }
        return derivedTermStart(from: snapshot.courses, calendar: calendar)
    }

    static func derivedTermStart(from courses: [WidgetCourseSnapshot], calendar source: Calendar = .current) -> Date? {
        let calendar = gregorian(source)
        var votes: [Date: Int] = [:]
        for course in courses {
            guard (1...7).contains(course.weekday),
                  let week = course.weekIndices?.filter({ $0 > 0 && $0 < 10_000 }).min(),
                  let date = course.dates?.compactMap({ isoDate($0, calendar: calendar) }).min() else { continue }
            let offset = (week - 1) * 7 + course.weekday - 1
            guard let start = calendar.date(byAdding: .day, value: -offset, to: date) else { continue }
            votes[calendar.startOfDay(for: start), default: 0] += 1
        }
        return votes.sorted {
            $0.value == $1.value ? $0.key > $1.key : $0.value > $1.value
        }.first?.key
    }

    static func currentWeek(termStart: Date?, on date: Date, calendar source: Calendar = .current) -> Int {
        guard let termStart else { return 1 }
        let calendar = gregorian(source)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: termStart),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        // Do not repeat week 20 forever after a semester has finished.
        return max(1, days / 7 + 1)
    }

    static func courses(_ courses: [WidgetCourseSnapshot], in week: Int) -> [WidgetCourseSnapshot] {
        var seen = Set<String>()
        return courses.filter { course in
            guard (1...5).contains(course.weekday) else { return false }
            if let weeks = course.weekIndices, !weeks.isEmpty, !weeks.contains(week) { return false }
            let key = [course.name, course.teacher, course.location, String(course.weekday), course.startTime, course.endTime]
                .joined(separator: "|")
            return seen.insert(key).inserted
        }
    }

    static func nextRefresh(after date: Date, hasScheduleData: Bool = true, calendar source: Calendar = .current) -> Date {
        let calendar = gregorian(source)
        let interval: TimeInterval = hasScheduleData ? 30 * 60 : 15 * 60
        let midnight = calendar.nextDate(after: date, matching: DateComponents(hour: 0, minute: 1),
                                         matchingPolicy: .nextTime) ?? date.addingTimeInterval(interval)
        return min(midnight, date.addingTimeInterval(interval))
    }

    private static func isoDate(_ text: String, calendar: Calendar) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: text), formatter.string(from: date) == text else { return nil }
        return date
    }
}
