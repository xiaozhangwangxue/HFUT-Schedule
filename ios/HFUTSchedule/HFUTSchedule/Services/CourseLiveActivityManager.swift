import ActivityKit
import Foundation

struct CourseLiveActivityInputs {
    let courses: [Course]
    let exams: [AcademicExam]
    let events: [CustomEvent]
    var termStart: Date? = nil
}

@MainActor
final class CourseLiveActivityManager: ObservableObject {
    static let shared = CourseLiveActivityManager()
    static let enabledKey = "courseLiveActivitiesEnabled"
    @Published private(set) var status: String?
    @Published var isEnabled: Bool {
        didSet {
            generation = UUID()
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            if !isEnabled { Task { await endAll() } }
        }
    }
    private var generation = UUID()
    private var foregroundTask: Task<Void, Never>?
    init() { isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey) }

    func startForegroundUpdates(_ inputs: @escaping @MainActor () -> CourseLiveActivityInputs) {
        foregroundTask?.cancel()
        foregroundTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let value = inputs()
                let now = Date()
                if self.isEnabled {
                    await self.refresh(courses: value.courses, exams: value.exams, events: value.events,
                        termStart: value.termStart, now: now)
                }
                guard !Task.isCancelled else { return }
                let occurrences = PlatformScheduleResolver.occurrences(courses: value.courses, exams: value.exams,
                    events: value.events, termStart: value.termStart ?? ScheduleCalendar.termStart(from: value.courses))
                let next = Self.nextForegroundRefresh(occurrences, now: Date())
                let delay = max(0.05, min(60, next.timeIntervalSinceNow))
                do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
                catch { return }
            }
        }
    }
    func stopForegroundUpdates() {
        foregroundTask?.cancel(); foregroundTask = nil
        generation = UUID()
    }
    nonisolated static func nextForegroundRefresh(_ items: [PlatformScheduleOccurrence], now: Date) -> Date {
        let boundary = items.filter { $0.kind != .deadline }.flatMap { [$0.start.addingTimeInterval(-900), $0.start, $0.end] }
            .filter { $0 > now }.min() ?? now.addingTimeInterval(60)
        return min(now.addingTimeInterval(60), boundary)
    }

    /// ActivityKit permits a local start while the app is in the foreground.
    /// This method doesn't promise future starts while a closed app cannot run.
    func refresh(courses: [Course], exams: [AcademicExam], events: [CustomEvent],
                 termStart: Date? = nil, now: Date = Date()) async {
        let token = UUID(); generation = token
        guard isEnabled else { await endAll(); return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            status = "系统未允许实时活动，请在 App 的系统设置中开启。"
            await endAll(); return
        }
        let items = PlatformScheduleResolver.occurrences(courses: courses, exams: exams, events: events,
            termStart: termStart ?? ScheduleCalendar.termStart(from: courses))
        let relevant = Self.currentOrSoon(items, now: now)
        for activity in Activity<CourseActivityAttributes>.activities where activity.attributes.occurrenceID != relevant?.id {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        guard generation == token, isEnabled else { return }
        guard let item = relevant else { status = "当前没有正在进行或 15 分钟内开始的课程、考试或日程。"; return }
        let state = CourseActivityAttributes.ContentState(title: item.title, location: item.location,
            start: item.start, end: item.end, kind: item.kind.rawValue)
        let content = ActivityContent(state: state, staleDate: item.end)
        if let existing = Activity<CourseActivityAttributes>.activities.first(where: { $0.attributes.occurrenceID == item.id }) {
            await existing.update(content)
        } else {
            do {
                _ = try Activity.request(attributes: CourseActivityAttributes(occurrenceID: item.id,
                    route: item.routeURL?.absoluteString ?? "hfut-schedule://home"), content: content, pushType: nil)
            } catch { status = "实时活动未能启动：\(error.localizedDescription)"; return }
        }
        status = "正在显示：\(item.title)"
    }

    func endAll() async {
        generation = UUID()
        for activity in Activity<CourseActivityAttributes>.activities { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    nonisolated static func currentOrSoon(_ items: [PlatformScheduleOccurrence], now: Date) -> PlatformScheduleOccurrence? {
        let eligible = items.filter { $0.kind != .deadline && $0.end > now && $0.start <= now.addingTimeInterval(15 * 60) }
        // Prefer an ongoing occurrence over a future one; stable tie-breaking.
        return eligible.sorted {
            let lhs = $0.start <= now, rhs = $1.start <= now
            if lhs != rhs { return lhs }
            return $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start
        }.first
    }
}
