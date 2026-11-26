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
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.kind == "exam" ? "考试" : "课程", systemImage: context.state.kind == "exam" ? "pencil" : "book")
                        .font(.caption.weight(.medium)).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.end, style: .time).font(.caption.monospacedDigit()).lineLimit(1)
                }
                // Keep the long title below the camera and away from the outer
                // rounded corners. The upper wings contain short labels only.
                DynamicIslandExpandedRegion(.bottom) {
                    CourseActivityExpandedContent(state: context.state)
                }
            } compactLeading: {
                Image(systemName: context.state.kind == "exam" ? "pencil" : "book").font(.caption)
            } compactTrailing: {
                Text(timerInterval: context.state.start...context.state.end, countsDown: true, showsHours: false)
                    .font(.caption2.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.8)
                    .frame(width: 44).padding(.trailing, 2)
            } minimal: {
                Image(systemName: context.state.kind == "exam" ? "pencil" : "book").font(.caption)
            }
            .contentMargins(.horizontal, 16, for: .expanded)
            .contentMargins(.bottom, 12, for: .expanded)
            .widgetURL(URL(string: context.attributes.route)).keylineTint(.blue)
        }
    }
}
