import Foundation

struct CustomEvent: Identifiable, Codable, Equatable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case event, deadline
        var id: String { rawValue }
        var title: String { self == .event ? "普通日程" : "截止事项" }
    }

    var id = UUID()
    var title: String
    var detail: String = ""
    var location: String = ""
    var start: Date
    var end: Date
    var kind: Kind = .event
    // 与上游一致，预留分组字段；多日期选择尚未在上游启用。
    var groupID: String? = nil

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && end >= start
    }

    func cloned() -> CustomEvent {
        var copy = self
        copy.id = UUID()
        copy.groupID = nil
        return copy
    }

    func appears(on date: Date, showExpired: Bool, calendar: Calendar = .current) -> Bool {
        if end < date { return showExpired }
        return true
    }

    func isImportant(on date: Date, calendar: Calendar = .current) -> Bool {
        if kind == .deadline { return (0...72 * 3600).contains(end.timeIntervalSince(date)) }
        return calendar.isDate(start, inSameDayAs: date) || (start <= date && end >= date)
    }

    /// 普通日程按自然日投影到课表；跨天日程在每一天显示对应的时间段。
    func timetableCourses(in weekStart: Date, calendar: Calendar = .current) -> [Course] {
        guard kind == .event else { return [] }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm"
        return (0..<7).compactMap { day in
            guard let date = calendar.date(byAdding: .day, value: day, to: calendar.startOfDay(for: weekStart)),
                  let next = calendar.date(byAdding: .day, value: 1, to: date), start < next, end > date else { return nil }
            // 一个日程跨多天时仍使用同一 ID；点击任一日期均编辑同一日程。
            return Course(id: id, name: title, teacher: "", location: location,
                weekday: day + 1, startTime: formatter.string(from: max(start, date)),
                endTime: end >= next ? "24:00" : formatter.string(from: end), colorIndex: 4,
                source: "custom-event", details: CourseDetails(remark: detail))
        }
    }
}
