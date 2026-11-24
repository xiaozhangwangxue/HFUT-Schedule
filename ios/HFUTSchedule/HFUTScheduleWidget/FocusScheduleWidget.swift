import AppIntents
import SwiftUI
import WidgetKit

struct RefreshFocusWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "刷新聚焦小组件"
    func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadTimelines(ofKind: FocusWidgetSnapshotStore.widgetKind)
        return .result()
    }
}

private struct FocusEntry: TimelineEntry {
    let date: Date
    let snapshot: FocusWidgetSnapshot?
}

private struct FocusProvider: TimelineProvider {
    func placeholder(in context: Context) -> FocusEntry { FocusEntry(date: .now, snapshot: nil) }
    func getSnapshot(in context: Context, completion: @escaping (FocusEntry) -> Void) {
        completion(FocusEntry(date: .now, snapshot: FocusWidgetSnapshotStore.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<FocusEntry>) -> Void) {
        let now = Date()
        let snapshot = FocusWidgetSnapshotStore.load()
        let dates = FocusWidgetProjection.refreshDates(snapshot, now: now)
        completion(Timeline(entries: dates.map { FocusEntry(date: $0, snapshot: snapshot) },
            policy: .after(now.addingTimeInterval(30 * 60))))
    }
}

private struct FocusWidgetView: View {
    let entry: FocusEntry
    @Environment(\.widgetFamily) private var family
    private var scale: Double { entry.snapshot?.fontScale ?? 1 }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(day?.isTomorrow == true ? "明天" : "今天").font(.system(size: 16 * scale, weight: .bold))
                if family != .systemSmall { Text((day?.date ?? entry.date).formatted(.dateTime.month().day())).font(.caption).foregroundStyle(.secondary) }
                Spacer(minLength: 2)
                Button(intent: RefreshFocusWidgetIntent()) { Image(systemName: "arrow.clockwise").font(.caption) }.buttonStyle(.plain).accessibilityLabel("刷新聚焦小组件")
            }
            if let day {
                if day.items.isEmpty {
                    Spacer(minLength: 0)
                    Label("没有课程或日程", systemImage: "calendar.badge.checkmark").font(.system(size: 12 * scale)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                } else {
                    let limit = family == .systemSmall ? 2 : (family == .systemMedium ? 3 : 7)
                    ForEach(Array(day.items.prefix(limit))) { item in
                        Link(destination: URL(string: item.route) ?? URL(string: "hfut-schedule://home")!) {
                            HStack(alignment: .top, spacing: 7) {
                                RoundedRectangle(cornerRadius: 2).fill(item.start <= entry.date && item.end > entry.date ? Color.green : Color.accentColor).frame(width: 3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).font(.system(size: 12 * scale, weight: .semibold)).lineLimit(1)
                                    Text("\(item.start.formatted(date: .omitted, time: .shortened)) · \(item.location)")
                                        .font(.system(size: 10 * scale)).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }.fixedSize(horizontal: false, vertical: true)
                        }.buttonStyle(.plain)
                    }
                    if day.items.count > limit { Text("还有 \(day.items.count - limit) 项，打开 App 查看").font(.caption2).foregroundStyle(.secondary) }
                    Spacer(minLength: 0)
                }
            } else {
                Spacer(minLength: 0)
                Text("打开 App 同步课表与考试").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }.padding(12).id(entry.snapshot?.revision)
            .containerBackground(.background, for: .widget).widgetURL(URL(string: "hfut-schedule://home"))
    }
    private var day: FocusWidgetDay? { entry.snapshot.map { FocusWidgetProjection.day($0, now: entry.date) } }
}

struct FocusScheduleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: FocusWidgetSnapshotStore.widgetKind, provider: FocusProvider()) { FocusWidgetView(entry: $0) }
            .configurationDisplayName("聚焦 · 今天与明天")
            .description("显示课程、考试和日程；今天课程结束后自动显示明天，可在 App 中调整字号。")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge]).contentMarginsDisabled()
    }
}
