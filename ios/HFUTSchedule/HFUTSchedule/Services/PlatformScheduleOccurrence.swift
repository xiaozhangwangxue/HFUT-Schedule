import Foundation

/// A concrete occurrence, rather than a weekday recurrence. Shared by calendar,
/// reminders and Live Activities so odd/even weeks and explicit dates agree.
struct PlatformScheduleOccurrence: Identifiable, Codable, Equatable {
    enum Kind: String, Codable { case course, exam, event, deadline }
    let id: String
    let sourceID: String
    let kind: Kind
    let title: String
    let location: String
    let detail: String
    let start: Date
    let end: Date

    var routeURL: URL? {
        var parts = URLComponents()
        parts.scheme = "hfut-schedule"
        parts.host = "occurrence"
        parts.queryItems = [URLQueryItem(name: "kind", value: kind.rawValue),
                            URLQueryItem(name: "id", value: sourceID),
                            URLQueryItem(name: "start", value: String(start.timeIntervalSince1970))]
        return parts.url
    }
}

enum PlatformScheduleResolver {
    static func occurrences(
        courses: [Course], exams: [AcademicExam] = [], events: [CustomEvent] = [],
        termStart: Date?, semesterWeeks: Int = 20, calendar source: Calendar = .current
    ) -> [PlatformScheduleOccurrence] {
        let calendar = WidgetScheduleCalendar.gregorian(source)
        var values: [PlatformScheduleOccurrence] = []
        for course in courses {
            var days: [Date] = []
            // Server dates are authoritative, including one-off changes.
            if let explicit = course.dates, !explicit.isEmpty {
                days = explicit.compactMap { date($0, calendar: calendar) }
            } else if let termStart, (1...7).contains(course.weekday) {
                let weeks = course.weekIndices?.isEmpty == false ? course.weekIndices! : Array(1...max(1, min(60, semesterWeeks)))
                days = weeks.filter { (1...60).contains($0) }.compactMap {
                    calendar.date(byAdding: .day, value: ($0 - 1) * 7 + course.weekday - 1,
                                  to: calendar.startOfDay(for: termStart))
                }
            }
            for day in Set(days) {
                guard let start = clock(course.startTime, on: day, calendar: calendar),
                      let end = clock(course.endTime, on: day, calendar: calendar), end > start else { continue }
                values.append(PlatformScheduleOccurrence(
                    id: "course|\(course.id.uuidString)|\(Int(calendar.startOfDay(for: day).timeIntervalSince1970))", sourceID: course.id.uuidString,
                    kind: .course, title: course.name, location: course.location, detail: course.teacher,
                    start: start, end: end))
            }
        }
        values += UpcomingExamResolver.resolved(exams, calendar: calendar).map {
            PlatformScheduleOccurrence(id: "exam|\($0.id.uuidString)", sourceID: $0.id.uuidString, kind: .exam,
                title: $0.exam.name, location: $0.location, detail: $0.exam.dateTime, start: $0.start, end: $0.end)
        }
        values += events.filter(\.isValid).map {
            PlatformScheduleOccurrence(id: "event|\($0.id.uuidString)", sourceID: $0.id.uuidString,
                kind: $0.kind == .deadline ? .deadline : .event, title: $0.title, location: $0.location,
                detail: $0.detail, start: $0.start, end: max($0.end, $0.start.addingTimeInterval(60)))
        }
        var seen = Set<String>()
        return values.filter { seen.insert($0.id).inserted }.sorted {
            $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start
        }
    }

    static func date(_ text: String, calendar: Calendar) -> Date? {
        CampusDateCodec.date(text, calendar: calendar)
    }

    private static func clock(_ text: String, on day: Date, calendar: Calendar) -> Date? {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0...24).contains(parts[0]), (0...59).contains(parts[1]),
              parts[0] != 24 || parts[1] == 0 else { return nil }
        if parts[0] == 24 { return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)) }
        return calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day)
    }
}

struct PlatformReminder: Equatable {
    let occurrence: PlatformScheduleOccurrence
    let fireDate: Date
}

enum PlatformReminderPlanner {
    /// Leave space for notifications owned by other app features. Each concrete
    /// lesson gets one non-repeating request; holidays cannot repeat forever.
    static func reminders(_ occurrences: [PlatformScheduleOccurrence], leadMinutes: Int,
                          now: Date, limit: Int = 60) -> [PlatformReminder] {
        occurrences.compactMap { item -> PlatformReminder? in
            let relevantDate = item.kind == .deadline ? item.end : item.start
            let fire = relevantDate.addingTimeInterval(-Double(max(0, min(1_440, leadMinutes))) * 60)
            return fire > now ? PlatformReminder(occurrence: item, fireDate: fire) : nil
        }.sorted { $0.fireDate == $1.fireDate ? $0.occurrence.id < $1.occurrence.id : $0.fireDate < $1.fireDate }
            .prefix(max(0, min(60, limit))).map { $0 }
    }
}
