import SwiftUI

struct PlatformWidgetsSettingsView: View {
    @EnvironmentObject private var schedule: ScheduleStore
    @EnvironmentObject private var records: AcademicRecordsStore
    @EnvironmentObject private var events: CustomEventStore
    @ObservedObject private var live = CourseLiveActivityManager.shared
    @AppStorage(FocusWidgetPublisher.fontScaleKey) private var fontScale = 1.0
    @AppStorage(FocusWidgetPublisher.tomorrowKey) private var tomorrow = true
    @State private var syncStatus: String?
    var body: some View {
        Form {
            Section("聚焦小组件") {
                Toggle("当天课程结束后显示明天", isOn: $tomorrow)
                LabeledContent("字号", value: "\(Int(fontScale * 100))%")
                Slider(value: $fontScale, in: 0.8...1.5, step: 0.1)
                Button("同步并请求刷新") { publish() }
                Text("在桌面添加“聚焦 · 今天与明天”。刷新时机由 iOS 调度；重新签名时需保留 App 与扩展的共享访问组。")
                    .font(.footnote).foregroundStyle(.secondary)
                if let syncStatus { Text(syncStatus).font(.footnote) }
            }
            Section("实时活动") {
                Toggle("课程、考试与日程实时活动", isOn: $live.isEnabled)
                Button("刷新当前安排") { Task { await refreshLive() } }
                Button("结束全部实时活动", role: .destructive) { Task { await live.endAll() } }
                Text("打开 App 时更新正在进行或 15 分钟内开始的安排。锁屏和灵动岛会显示时间进度；App 完全关闭后无法保证自动启动下一项。")
                    .font(.footnote).foregroundStyle(.secondary)
                if let status = live.status { Text(status).font(.footnote) }
            }
        }.navigationTitle("聚焦组件与实时活动")
            .onChange(of: fontScale) { _, _ in publish() }
            .onChange(of: tomorrow) { _, _ in publish() }
            .onChange(of: live.isEnabled) { _, enabled in if enabled { Task { await refreshLive() } } }
    }
    private func publish() {
        let written = FocusWidgetPublisher.publish(schedule: schedule, exams: records.exams, events: events.events)
        syncStatus = written ? "快照已同步，已向 iOS 请求刷新。" : "共享快照写入失败，请检查重新签名时是否保留共享访问组。"
    }
    private func refreshLive() async {
        await live.refresh(courses: schedule.courses, exams: records.exams, events: events.events)
    }
}
