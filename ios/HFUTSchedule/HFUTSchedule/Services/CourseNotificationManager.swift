import Foundation
import UserNotifications

extension Notification.Name { static let platformRouteRequested = Notification.Name("HFUTPlatformRouteRequested") }

/// Keep a strong owner in the app: UNUserNotificationCenter's delegate is weak.
final class CourseNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = CourseNotificationDelegate()
    func install() { UNUserNotificationCenter.current().delegate = self }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let value = response.notification.request.content.userInfo["routeURL"] as? String,
           let url = URL(string: value), ["hfut-schedule", "hfut_schedule"].contains(url.scheme?.lowercased() ?? "") {
            UserDefaults.standard.set(value, forKey: "pendingPlatformURL")
            Task { @MainActor in NotificationCenter.default.post(name: .platformRouteRequested, object: url) }
        }
        completionHandler()
    }
}

@MainActor
final class CourseNotificationManager: ObservableObject {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var pendingReminderCount = 0
    @Published private(set) var schedulingNote: String?
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "courseRemindersEnabled") }
    }
    @Published var leadMinutes: Int {
        didSet { UserDefaults.standard.set(leadMinutes, forKey: "courseReminderLeadMinutes") }
    }
    private let center = UNUserNotificationCenter.current()
    private let identifierPrefix = "course-reminder-"
    private var generation = UUID()
    // Existing course-only call sites retain exams/custom events last supplied
    // by the app-wide data observer rather than silently clearing them.
    private var cachedExams: [AcademicExam] = []
    private var cachedEvents: [CustomEvent] = []

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

    func reschedule(for courses: [Course], exams: [AcademicExam]? = nil, events: [CustomEvent]? = nil,
                    termStart: Date? = nil, now: Date = Date()) async throws {
        if let exams { cachedExams = exams }
        if let events { cachedEvents = events }
        let token = UUID()
        generation = token
        let pending = await center.pendingNotificationRequests()
        guard generation == token else { return }
        let oldIdentifiers = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: oldIdentifiers)
        schedulingNote = nil
        guard isEnabled else { await refresh(); return }
        let settings = await center.notificationSettings()
        guard generation == token else { return }
        if settings.authorizationStatus == .notDetermined {
            guard try await requestAuthorization() else { throw ReminderError.permissionDenied }
        } else if settings.authorizationStatus == .denied { throw ReminderError.permissionDenied }
        guard generation == token else { return }

        let resolvedStart = termStart ?? ScheduleCalendar.termStart(from: courses)
        let exams = cachedExams, events = cachedEvents
        let occurrences = await Task.detached(priority: .utility) {
            PlatformScheduleResolver.occurrences(courses: courses, exams: exams, events: events, termStart: resolvedStart)
        }.value
        guard generation == token else { return }
        let otherCount = pending.filter { !$0.identifier.hasPrefix(identifierPrefix) }.count
        let reminders = PlatformReminderPlanner.reminders(occurrences, leadMinutes: leadMinutes,
            now: now, limit: max(0, 64 - otherCount))
        var added: [String] = []
        do {
            for reminder in reminders {
                guard generation == token else { center.removePendingNotificationRequests(withIdentifiers: added); return }
                let item = reminder.occurrence
                let content = UNMutableNotificationContent()
                let prefix = switch item.kind {
                    case .course: "即将上课"
                    case .exam: "即将考试"
                    case .event: "日程提醒"
                    case .deadline: "即将截止"
                }
                content.title = "\(prefix)：\(item.title)"
                content.body = [item.location, item.detail].filter { !$0.isEmpty }.joined(separator: " · ")
                content.sound = .default
                content.threadIdentifier = "schedule-reminders"
                content.userInfo = ["routeURL": item.routeURL?.absoluteString ?? "hfut-schedule://schedule",
                                    "courseID": item.sourceID, "kind": item.kind.rawValue]
                var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.fireDate)
                components.timeZone = .current
                let identifier = identifierPrefix + token.uuidString + "-" + item.id
                let request = UNNotificationRequest(identifier: identifier, content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
                try await center.add(request)
                added.append(identifier)
            }
        } catch {
            center.removePendingNotificationRequests(withIdentifiers: added)
            throw error
        }
        guard generation == token else { center.removePendingNotificationRequests(withIdentifiers: added); return }
        if resolvedStart == nil && courses.contains(where: { $0.dates?.isEmpty != false }) {
            schedulingNote = "部分课程没有实际日期，请设置学期开始日后刷新提醒。"
        } else if reminders.count == 60 {
            schedulingNote = "已安排最近 60 项提醒；每次打开 App 和修改日程时会继续补充。"
        }
        await refresh()
    }
}

enum ReminderError: LocalizedError {
    case permissionDenied
    var errorDescription: String? { "请在系统设置中允许“聚在工大”发送通知。" }
}
