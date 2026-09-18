import Foundation
import UserNotifications

@MainActor
final class CourseNotificationManager: ObservableObject {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var pendingReminderCount = 0
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "courseRemindersEnabled") }
    }
    @Published var leadMinutes: Int {
        didSet { UserDefaults.standard.set(leadMinutes, forKey: "courseReminderLeadMinutes") }
    }

    private let center = UNUserNotificationCenter.current()
    private let identifierPrefix = "course-reminder-"

    init() {
        isEnabled = UserDefaults.standard.bool(forKey: "courseRemindersEnabled")
        let savedLead = UserDefaults.standard.integer(forKey: "courseReminderLeadMinutes")
        leadMinutes = savedLead > 0 ? savedLead : 15
    }

    var authorizationDescription: String {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral: "已授权"
        case .denied: "已关闭"
        case .notDetermined: "尚未请求"
        @unknown default: "未知"
        }
    }

    func refresh() async {
        authorizationStatus = await center.notificationSettings().authorizationStatus
        let requests = await center.pendingNotificationRequests()
        pendingReminderCount = requests.filter { $0.identifier.hasPrefix(identifierPrefix) }.count
    }

    @discardableResult
    func requestAuthorization() async throws -> Bool {
        let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
        await refresh()
        return granted
    }

    func reschedule(for courses: [Course]) async throws {
        let pending = await center.pendingNotificationRequests()
        let oldIdentifiers = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: oldIdentifiers)

        guard isEnabled, !courses.isEmpty else {
            await refresh()
            return
        }

        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            guard try await requestAuthorization() else { throw ReminderError.permissionDenied }
        } else if settings.authorizationStatus == .denied {
            throw ReminderError.permissionDenied
        }

        for course in courses {
            guard let components = reminderComponents(for: course) else { continue }
            let content = UNMutableNotificationContent()
            content.title = "即将上课：\(course.name)"
            let details = [course.location, course.teacher].filter { !$0.isEmpty }.joined(separator: " · ")
            content.body = details.isEmpty ? "\(leadMinutes) 分钟后开始" : "\(details) · \(leadMinutes) 分钟后开始"
            content.sound = .default
            content.threadIdentifier = "course-reminders"
            content.userInfo = ["courseID": course.id.uuidString]

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(
                identifier: identifierPrefix + course.id.uuidString,
                content: content,
                trigger: trigger
            )
            try await center.add(request)
        }
        await refresh()
    }

    private func reminderComponents(for course: Course) -> DateComponents? {
        guard let time = Self.parseTime(course.startTime) else { return nil }
        var base = DateComponents()
        base.calendar = .current
        base.timeZone = .current
        base.year = 2024
        base.month = 1
        base.day = 1 + max(0, min(6, course.weekday - 1))
        base.hour = Calendar.current.component(.hour, from: time)
        base.minute = Calendar.current.component(.minute, from: time)
        guard let courseDate = Calendar.current.date(from: base),
              let reminderDate = Calendar.current.date(byAdding: .minute, value: -leadMinutes, to: courseDate)
        else { return nil }
        return Calendar.current.dateComponents([.weekday, .hour, .minute], from: reminderDate)
    }

    private static func parseTime(_ value: String) -> Date? {
        let formats = ["HH:mm", "H:mm", "h:mm a", "hh:mm a"]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = .current
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}

enum ReminderError: LocalizedError {
    case permissionDenied

    var errorDescription: String? {
        "请在系统设置中允许“聚在工大”发送通知。"
    }
}
