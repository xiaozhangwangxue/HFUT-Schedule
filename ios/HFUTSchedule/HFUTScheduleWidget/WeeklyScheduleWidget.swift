import SwiftUI
import WidgetKit

private struct WeeklyScheduleEntry: TimelineEntry {
    let date: Date
    let week: Int
    let monday: Date?
    let courses: [WidgetCourseSnapshot]
    let hasScheduleData: Bool

    var viewData: WeeklyScheduleViewData {
        WeeklyScheduleViewData(date: date, week: week, monday: monday, courses: courses, hasScheduleData: hasScheduleData)
    }
}

private struct WeeklyScheduleProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeeklyScheduleEntry {
        WeeklyScheduleEntry(
            date: .now,
            week: 2,
            monday: WidgetScheduleCalendar.gregorian().dateInterval(of: .weekOfYear, for: .now)?.start,
            courses: Self.previewCourses,
            hasScheduleData: true
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (WeeklyScheduleEntry) -> Void) {
        completion(entry(previewWhenEmpty: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeeklyScheduleEntry>) -> Void) {
        let current = entry(previewWhenEmpty: false)
        completion(Timeline(entries: [current], policy: .after(WidgetScheduleCalendar.nextRefresh(
            after: current.date, hasScheduleData: current.hasScheduleData
        ))))
    }

    private func entry(previewWhenEmpty: Bool, date: Date = .now) -> WeeklyScheduleEntry {
        // The bridge acknowledges only App Group / shared-keychain snapshots.
        // A filtered empty week still proves that schedule data was received.
        let result = WidgetSnapshotStore.loadResult(acknowledge: true)
        let projected = WidgetScheduleCalendar.project(result.snapshot, on: date)
        let showPreview = previewWhenEmpty && !result.hasScheduleData
        return WeeklyScheduleEntry(
            date: date,
            week: projected.week,
            monday: projected.monday,
            courses: showPreview ? Self.previewCourses : projected.courses,
            hasScheduleData: result.hasScheduleData || showPreview
        )
    }

    private static let previewCourses: [WidgetCourseSnapshot] = [
        snapshot("高等数学", "", "教学楼 A101", 1, "08:00", "09:40", 0),
        snapshot("程序设计", "", "计算机楼 102", 1, "10:00", "11:40", 1),
        snapshot("大学英语", "", "教学楼 B305", 2, "10:00", "11:40", 0),
        snapshot("思想道德与法治", "", "教学楼 A201", 2, "14:00", "15:40", 4),
        snapshot("线性代数", "", "教学楼 A101", 3, "10:00", "11:40", 1),
        snapshot("大学物理", "", "实验楼 C203", 4, "10:00", "11:40", 3),
        snapshot("体育", "", "体育场", 4, "14:00", "15:40", 2),
        snapshot("大学英语", "", "教学楼 B305", 5, "08:00", "09:40", 3),
        snapshot("高等数学", "", "教学楼 A101", 5, "10:00", "11:40", 1),
        snapshot("程序设计", "", "计算机楼 102", 5, "15:50", "17:30", 0)
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
            .widgetURL(URL(string: "hfut-schedule://schedule"))
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
