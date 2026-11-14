import Foundation
import CryptoKit

struct AcademicExamTiming: Equatable {
    let start: Date
    let end: Date
}

struct ResolvedAcademicExam: Identifiable, Equatable {
    let exam: AcademicExam
    let start: Date
    let end: Date
    let location: String
    let id: UUID
}

/// Shared projections of cached exam records for the timetable and Focus.
/// Upstream Focus shows every future exam, with no 72-hour cutoff. The 72-hour
/// threshold belongs only to user-created deadline events (FocusItems.kt).
enum UpcomingExamResolver {
    static func timing(for exam: AcademicExam, calendar suppliedCalendar: Calendar = .current) -> AcademicExamTiming? {
        let calendar = gregorian(suppliedCalendar)
        let text = exam.dateTime.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? exam.dateTime
        let dates = matches(#"(?<![0-9])([0-9]{4})\s*[-/.年]\s*([0-9]{1,2})\s*[-/.月]\s*([0-9]{1,2})\s*日?(?![0-9])"#, in: text)
        let times = matches(#"(?<![0-9])(?:(凌晨|早上|上午|中午|下午|晚上|晚间)\s*)?([0-9]{1,2})\s*(?:(?:[:：]\s*([0-9]{1,2})(?:\s*[:：]\s*[0-9]{2})?)|(?:[时点](?:\s*([0-9]{1,2})\s*分?)?))(?![0-9])"#, in: text)
        guard (1...2).contains(dates.count), times.count == 2,
              let startDay = dateParts(dates[0]),
              let endDay = dateParts(dates.last!),
              let firstTime = timeParts(times[0], inheritedPeriod: nil),
              let secondTime = timeParts(times[1], inheritedPeriod: times[0][1]),
              let firstRange = times[0].range, let secondRange = times[1].range,
              firstRange.upperBound <= secondRange.lowerBound else { return nil }

        // Require an actual range, rather than interpreting unrelated times
        // such as "报到 08:00，考试 09:00" as an exam duration.
        var separator = String(text[firstRange.upperBound..<secondRange.lowerBound])
        if dates.count == 2 { separator = separator.replacingOccurrences(of: dates[1][0] ?? "", with: "") }
        separator = separator.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ["~", "～", "-", "—", "–", "－", "至", "到"].contains(separator),
              let start = makeDate(day: startDay, time: firstTime, calendar: calendar),
              let end = makeDate(day: endDay, time: secondTime, calendar: calendar), end > start else { return nil }
        return AcademicExamTiming(start: start, end: end)
    }

    /// Exam.kt JxglstuExamUI(status=false): dates from today onward, retaining
    /// today's exam through its ending minute. No arbitrary future-day limit.
    static func focusExams(
        _ exams: [AcademicExam], now: Date = Date(), calendar suppliedCalendar: Calendar = .current
    ) -> [ResolvedAcademicExam] {
        let calendar = gregorian(suppliedCalendar)
        let today = calendar.startOfDay(for: now)
        let minute = calendar.dateInterval(of: .minute, for: now)?.start ?? now
        return resolved(exams, calendar: calendar).filter {
            calendar.startOfDay(for: $0.start) >= today && $0.end >= minute
        }
    }

    /// DataAdapter.examToTimeTableData maps every valid exam to its natural
    /// calendar date. Historical exams remain visible when selecting that week.
    static func timetableCourses(
        _ exams: [AcademicExam], inWeekStarting weekStart: Date,
        calendar suppliedCalendar: Calendar = .current
    ) -> [Course] {
        let calendar = gregorian(suppliedCalendar)
        let firstDay = calendar.startOfDay(for: weekStart)
        return resolved(exams, calendar: calendar).flatMap { item in
            (0..<7).compactMap { offset -> Course? in
                guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay),
                      let next = calendar.date(byAdding: .day, value: 1, to: day),
                      item.start < next, item.end > day else { return nil }
                return Course(
                    id: item.id, name: item.exam.name.trimmingCharacters(in: .whitespacesAndNewlines),
                    teacher: "", location: item.location, weekday: offset + 1,
                    startTime: clock(max(item.start, day), calendar: calendar),
                    endTime: item.end >= next ? "24:00" : clock(item.end, calendar: calendar),
                    colorIndex: 4, dates: [dateKey(day, calendar: calendar)], source: "exam",
                    details: CourseDetails(type: "考试", examMode: "考试", scheduleText: item.exam.dateTime)
                )
            }
        }
    }

    static func resolved(_ exams: [AcademicExam], calendar suppliedCalendar: Calendar = .current) -> [ResolvedAcademicExam] {
        let calendar = gregorian(suppliedCalendar)
        var byIdentity: [UUID: ResolvedAcademicExam] = [:]
        for exam in exams {
            let name = exam.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, let timing = timing(for: exam, calendar: calendar) else { continue }
            let id = stableID("exam|\(name)|\(timing.start.timeIntervalSince1970)|\(timing.end.timeIntervalSince1970)")
            let place = normalizedLocation(exam.place)
            let value = ResolvedAcademicExam(exam: exam, start: timing.start, end: timing.end,
                                            location: place.isEmpty ? "地点待定" : place, id: id)
            // The same exam can arrive through HTML and UniApp; prefer a record
            // with a usable room rather than drawing two overlapping blocks.
            if byIdentity[id] == nil || (byIdentity[id]?.location == "地点待定" && !place.isEmpty) {
                byIdentity[id] = value
            }
        }
        return byIdentity.values.sorted {
            $0.start == $1.start ? $0.id.uuidString < $1.id.uuidString : $0.start < $1.start
        }
    }

    static func exam(
        forCourseID id: UUID, in exams: [AcademicExam], calendar: Calendar = .current
    ) -> ResolvedAcademicExam? {
        resolved(exams, calendar: calendar).first { $0.id == id }
    }

    private struct Match {
        let captures: [String?]
        let range: Range<String.Index>?
        subscript(_ index: Int) -> String? { captures.indices.contains(index) ? captures[index] : nil }
    }

    private static func matches(_ pattern: String, in text: String) -> [Match] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            Match(captures: (0..<match.numberOfRanges).map {
                Range(match.range(at: $0), in: text).map { String(text[$0]) }
            }, range: Range(match.range, in: text))
        }
    }

    private static func dateParts(_ match: Match) -> (Int, Int, Int)? {
        guard let year = match[1].flatMap(Int.init), year > 0,
              let month = match[2].flatMap(Int.init), (1...12).contains(month),
              let day = match[3].flatMap(Int.init), (1...31).contains(day) else { return nil }
        return (year, month, day)
    }

    private static func timeParts(_ match: Match, inheritedPeriod: String?) -> (Int, Int)? {
        guard var hour = match[2].flatMap(Int.init),
              let minute = Int(match[3] ?? match[4] ?? "0"),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        if let period = match[1] ?? inheritedPeriod {
            guard (1...12).contains(hour) else { return nil }
            if ["中午", "下午", "晚上", "晚间"].contains(period) {
                if hour < 12 { hour += 12 }
            } else if hour == 12 { hour = 0 }
        }
        return (hour, minute)
    }

    private static func makeDate(day: (Int, Int, Int), time: (Int, Int), calendar: Calendar) -> Date? {
        let parts = DateComponents(year: day.0, month: day.1, day: day.2, hour: time.0, minute: time.1)
        guard let date = calendar.date(from: parts) else { return nil }
        let actual = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard actual.year == day.0, actual.month == day.1, actual.day == day.2,
              actual.hour == time.0, actual.minute == time.1 else { return nil }
        return date
    }

    private static func gregorian(_ source: Calendar) -> Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = source.timeZone
        result.firstWeekday = 2
        return result
    }

    private static func clock(_ date: Date, calendar: Calendar) -> String {
        String(format: "%02d:%02d", calendar.component(.hour, from: date), calendar.component(.minute, from: date))
    }

    private static func dateKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    private static func normalizedLocation(_ place: String) -> String {
        let value = place.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ["", "--", "—", "暂无", "未安排", "待定", "null", "nil"].contains(value.lowercased()) ? "" : value
    }

    private static func stableID(_ seed: String) -> UUID {
        let bytes = Array(SHA256.hash(data: Data(seed.utf8)).prefix(16))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
