import EventKit
import Foundation

enum CalendarExportError: LocalizedError {
    case permissionDenied
    case calendarUnavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "没有日历写入权限"
        case .calendarUnavailable: "未找到可写入的系统日历"
        }
    }
}

struct CalendarExporter {
    private let store = EKEventStore()

    func export(_ courses: [Course]) async throws -> Int {
        let allowed = try await store.requestFullAccessToEvents()
        guard allowed else { throw CalendarExportError.permissionDenied }
        guard let calendar = store.defaultCalendarForNewEvents else {
            throw CalendarExportError.calendarUnavailable
        }

        let calendarAPI = Calendar.current
        let startOfWeek = calendarAPI.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        var count = 0

        for course in courses {
            guard let hourMinute = parse(course.startTime),
                  let endHourMinute = parse(course.endTime),
                  let day = calendarAPI.date(byAdding: .day, value: max(0, course.weekday - 1), to: startOfWeek),
                  let start = calendarAPI.date(bySettingHour: hourMinute.0, minute: hourMinute.1, second: 0, of: day),
                  let end = calendarAPI.date(bySettingHour: endHourMinute.0, minute: endHourMinute.1, second: 0, of: day) else { continue }

            let event = EKEvent(eventStore: store)
            event.title = course.name
            event.location = course.location
            event.notes = course.teacher.isEmpty ? "由聚在工大 iOS 添加" : "任课教师：\(course.teacher)"
            event.startDate = start
            event.endDate = end
            event.calendar = calendar
            event.addAlarm(EKAlarm(relativeOffset: -15 * 60))
            try store.save(event, span: .thisEvent, commit: false)
            count += 1
        }
        try store.commit()
        return count
    }

    private func parse(_ value: String) -> (Int, Int)? {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return (parts[0], parts[1])
    }
}
