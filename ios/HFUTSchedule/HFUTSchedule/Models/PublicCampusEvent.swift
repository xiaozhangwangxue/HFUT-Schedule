import Foundation

struct PublicCampusEvent: Identifiable, Equatable {
    let title: String
    let time: String
    let detail: String
    let start: Date
    let end: Date
    let isDeadline: Bool
    var id: String { "\(title)|\(start.timeIntervalSince1970)|\(end.timeIntervalSince1970)|\(isDeadline)" }

    static func decode(_ value: Any?, deadline: Bool, calendar: Calendar = ScheduleCalendar.calendar) -> [Self] {
        (value as? [[String: Any]] ?? []).compactMap { row in
            guard row["showPublic"] as? Bool == true,
                  let title = row["title"] as? String,
                  let start = date(row["startTime"], calendar: calendar),
                  let end = date(row["endTime"], calendar: calendar), end >= start else { return nil }
            return Self(title: title, time: row["time"] as? String ?? "", detail: row["info"] as? String ?? "",
                start: start, end: end, isDeadline: deadline)
        }
    }

    private static func date(_ value: Any?, calendar: Calendar) -> Date? {
        guard let values = value as? [Int], values.count >= 5,
              (1...12).contains(values[1]), (1...31).contains(values[2]),
              (0...23).contains(values[3]), (0...59).contains(values[4]) else { return nil }
        let components = DateComponents(year: values[0], month: values[1], day: values[2], hour: values[3], minute: values[4])
        guard let date = calendar.date(from: components), calendar.component(.day, from: date) == values[2] else { return nil }
        return date
    }

    func isImportant(at now: Date, calendar: Calendar = ScheduleCalendar.calendar) -> Bool {
        if isDeadline { return end >= now && end.timeIntervalSince(now) <= 72 * 3600 }
        return calendar.isDate(start, inSameDayAs: now) || (start <= now && now <= end)
    }
}

enum LearningPlatform {
    static let presets = ["学习通", "U校园", "U校园AI版", "雨课堂", "中国大学MOOC"]

    static func url(for description: String) -> URL? {
        if description.contains("学习通") { return URL(string: "https://i.chaoxing.com/") }
        if description.contains("U校园") {
            return URL(string: description.localizedCaseInsensitiveContains("AI") ? "https://ucloud.unipus.cn/" : "https://u.unipus.cn/")
        }
        if description.contains("雨课堂") { return URL(string: "https://www.yuketang.cn/") }
        if description.localizedCaseInsensitiveContains("MOOC") { return URL(string: "https://www.icourse163.org/") }
        guard let url = URL(string: description.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    static func fallback(for description: String) -> URL? {
        description.contains("学习通") ? URL(string: "https://i.chaoxing.com/") : nil
    }
}
