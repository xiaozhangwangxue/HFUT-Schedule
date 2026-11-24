import SwiftUI

/// A notification/calendar/Live Activity route resolves against current data.
/// Deleted records show an honest empty state instead of an unrelated course.
struct PlatformOccurrenceDetailView: View {
    let destination: PlatformOccurrenceDestination
    @EnvironmentObject private var schedule: ScheduleStore
    @EnvironmentObject private var records: AcademicRecordsStore
    @EnvironmentObject private var events: CustomEventStore
    private var occurrence: PlatformScheduleOccurrence? {
        PlatformScheduleResolver.occurrences(courses: schedule.courses, exams: records.exams, events: events.events,
            termStart: ScheduleCalendar.termStart(from: schedule.courses)).first {
                $0.kind == destination.kind && $0.sourceID == destination.sourceID &&
                (destination.start == nil || abs($0.start.timeIntervalSince(destination.start!)) < 1)
            }
    }
    var body: some View {
        Group {
            if let occurrence {
                Form {
                    Section(occurrence.title) {
                        LabeledContent("开始", value: occurrence.start.formatted(date: .abbreviated, time: .shortened))
                        LabeledContent("结束", value: occurrence.end.formatted(date: .abbreviated, time: .shortened))
                        if !occurrence.location.isEmpty { LabeledContent("地点", value: occurrence.location) }
                        if !occurrence.detail.isEmpty { Text(occurrence.detail).textSelection(.enabled) }
                    }
                    Section { SingleCalendarExportButton(occurrence: occurrence) }
                }
            } else {
                ContentUnavailableView("日程已更新或已删除", systemImage: "calendar.badge.exclamationmark",
                    description: Text("请返回课表或聚焦查看最新安排。"))
            }
        }.navigationTitle("日程详情").navigationBarTitleDisplayMode(.inline)
    }
}
