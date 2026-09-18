import SwiftUI
import WidgetKit

private struct WeeklyScheduleEntry: TimelineEntry {
    let date: Date
    let week: Int
    let monday: Date?
    let courses: [WidgetCourseSnapshot]

    var viewData: WeeklyScheduleViewData {
        WeeklyScheduleViewData(date: date, week: week, monday: monday, courses: courses)
    }
}

private struct WeeklyScheduleProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeeklyScheduleEntry {
        WeeklyScheduleEntry(
            date: .now,
            week: 2,
            monday: Self.calendar.startOfDay(for: .now),
            courses: Self.previewCourses
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (WeeklyScheduleEntry) -> Void) {
        completion(entry(previewWhenEmpty: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeeklyScheduleEntry>) -> Void) {
        let current = entry(previewWhenEmpty: false)
        let nextMidnight = Self.calendar.nextDate(
            after: .now,
            matching: DateComponents(hour: 0, minute: 1),
            matchingPolicy: .nextTime
        ) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [current], policy: .after(nextMidnight)))
    }

    private func entry(previewWhenEmpty: Bool) -> WeeklyScheduleEntry {
        let allCourses = WidgetSnapshotStore.load()
        let termStart = Self.termStart(from: allCourses)
        let week = Self.currentWeek(termStart: termStart)
        let activeCourses = Self.courses(allCourses, in: week)
        return WeeklyScheduleEntry(
            date: .now,
            week: week,
            monday: Self.startDate(of: week, termStart: termStart),
            courses: activeCourses.isEmpty && previewWhenEmpty ? Self.previewCourses : activeCourses
        )
    }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = .current
        calendar.firstWeekday = 2
        return calendar
    }()

    private static func termStart(from courses: [WidgetCourseSnapshot]) -> Date? {
        for course in courses {
            guard let week = course.weekIndices?.sorted().first,
                  let text = course.dates?.sorted().first,
                  let date = isoDate(text) else { continue }
            let days = (week - 1) * 7 + max(0, course.weekday - 1)
            if let start = calendar.date(byAdding: .day, value: -days, to: date) {
                return calendar.startOfDay(for: start)
            }
        }
        return nil
    }

    private static func currentWeek(termStart: Date?) -> Int {
        guard let termStart else { return 1 }
        let days = calendar.dateComponents([.day], from: termStart, to: calendar.startOfDay(for: .now)).day ?? 0
        guard days >= 0 else { return 1 }
        return min(20, max(1, days / 7 + 1))
    }

    private static func startDate(of week: Int, termStart: Date?) -> Date? {
        guard let termStart else { return nil }
        return calendar.date(byAdding: .day, value: (week - 1) * 7, to: termStart)
    }

    private static func courses(_ courses: [WidgetCourseSnapshot], in week: Int) -> [WidgetCourseSnapshot] {
        var seen = Set<String>()
        return courses
            .filter { course in
                guard let weeks = course.weekIndices, !weeks.isEmpty else { return true }
                return weeks.contains(week)
            }
            .filter { course in
                let key = [course.name, course.teacher, course.location, String(course.weekday), course.startTime, course.endTime]
                    .joined(separator: "|")
                return seen.insert(key).inserted
            }
    }

    private static func isoDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)
    }

    private static let previewCourses: [WidgetCourseSnapshot] = [
        snapshot("高等数学A（上）", "李慧民", "翠五教304", 1, "08:00", "09:40", 0),
        snapshot("程序设计基础", "杨静", "翠十二教106", 1, "10:00", "11:40", 1),
        snapshot("高等数学A（上）", "李慧民", "翠五教304", 2, "10:00", "11:40", 0),
        snapshot("思想道德与法治", "江刚", "翠五教304", 2, "14:00", "15:40", 4),
        snapshot("线性代数", "檀敬东", "翠三教101", 3, "10:00", "11:40", 1),
        snapshot("程序设计基础", "杨静", "翠十二教106", 4, "10:00", "11:40", 3),
        snapshot("大学生心理健康", "胡倩倩", "翠四教112", 4, "14:00", "15:40", 2),
        snapshot("大学体育（1）", "童彦章", "体育场", 4, "15:50", "17:30", 0),
        snapshot("线性代数", "檀敬东", "翠三教101", 5, "08:00", "09:40", 3),
        snapshot("高等数学A（上）", "李慧民", "翠五教304", 5, "10:00", "11:40", 1),
        snapshot("思想道德与法治", "江刚", "翠五教304", 5, "15:50", "17:30", 0)
    ]

    private static func snapshot(
        _ name: String,
        _ teacher: String,
        _ location: String,
        _ weekday: Int,
        _ start: String,
        _ end: String,
        _ colorIndex: Int
    ) -> WidgetCourseSnapshot {
        WidgetCourseSnapshot(
            id: UUID(),
            name: name,
            teacher: teacher,
            location: location,
            weekday: weekday,
            startTime: start,
            endTime: end,
            colorIndex: colorIndex,
            weekIndices: nil,
            dates: nil
        )
    }
}

private struct WidgetRootView: View {
    let entry: WeeklyScheduleEntry

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        WeeklyScheduleWidgetView(data: entry.viewData)
            .containerBackground(for: .widget) {
                WidgetPalette.resolve(colorScheme).canvas
            }
    }
}

struct WeeklyScheduleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetScheduleBridge.widgetKind, provider: WeeklyScheduleProvider()) { entry in
            WidgetRootView(entry: entry)
        }
        .configurationDisplayName("周课表")
        .description("在桌面查看本周周一到周五的全部课程，今天高亮显示。")
        .supportedFamilies([.systemLarge])
        .contentMarginsDisabled()
    }
}
