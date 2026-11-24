import ActivityKit
import SwiftUI
import WidgetKit

struct CourseLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CourseActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(context.isStale ? "安排已结束，请打开 App 刷新" : (context.state.kind == "exam" ? "考试" : "课程与日程"), systemImage: "calendar")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text(context.state.start, style: .time).font(.caption.monospacedDigit())
                }.foregroundStyle(.secondary)
                Text(context.state.title).font(.headline).lineLimit(2)
                Text(context.state.location).font(.subheadline).lineLimit(1)
                ProgressView(timerInterval: context.state.start...context.state.end, countsDown: false)
                    .tint(.blue)
                HStack {
                    Text(context.state.start, style: .time)
                    Spacer()
                    Text(context.state.end, style: .time)
                }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }.padding(16).activityBackgroundTint(Color(.secondarySystemBackground))
                .widgetURL(URL(string: context.attributes.route))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: context.state.kind == "exam" ? "pencil.and.list.clipboard" : "books.vertical") }
                DynamicIslandExpandedRegion(.trailing) { Text(context.state.end, style: .time).font(.caption.monospacedDigit()) }
                DynamicIslandExpandedRegion(.center) { Text(context.state.title).font(.headline).lineLimit(1) }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        Text(context.state.location).font(.caption).lineLimit(1)
                        ProgressView(timerInterval: context.state.start...context.state.end, countsDown: false)
                    }
                }
            } compactLeading: { Image(systemName: context.state.kind == "exam" ? "pencil" : "book") }
              compactTrailing: { Text(context.state.end, style: .timer).monospacedDigit().frame(maxWidth: 50) }
              minimal: { Image(systemName: context.state.kind == "exam" ? "pencil" : "book") }
              .widgetURL(URL(string: context.attributes.route)).keylineTint(.blue)
        }
    }
}
