import SwiftUI

struct WidgetSyncSettingsView: View {
    @EnvironmentObject private var scheduleStore: ScheduleStore
    @State private var publication: WidgetPublicationStatus?
    @State private var acknowledged = false

    var body: some View {
        List {
            Section {
                LabeledContent("App 内课程时段", value: "\(scheduleStore.courses.count)")
                if let publication {
                    LabeledContent("最近发送", value: publication.publishedAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("发送的课程时段", value: "\(publication.courseCount)")
                    Label(statusText(publication), systemImage: acknowledged ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                        .foregroundStyle(acknowledged ? Color.green : Color.secondary)
                } else {
                    Text("尚未发送课表到小组件。")
                }
                if let message = scheduleStore.widgetSyncMessage {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
                Button("重新发送现有课表", systemImage: "arrow.clockwise") {
                    scheduleStore.refreshWidgetSnapshot(forceNewRevision: true)
                    updateStatus()
                }
            } header: {
                Text("同步状态")
            } footer: {
                Text("发送使用本机已有课表，无需重新登录。只有收到小组件的读取回执，才会显示“已读取”。")
            }

            Section("重新签名安装") {
                Text("签名时需要保留周课表扩展，并让 App 和扩展使用同一个共享钥匙串组。若工具分别生成独立分组，小组件就无法读取 App 的课程。")
                Text("更新后先打开 App 一次，再查看小组件。刷新由 iOS 调度，刚发送后可能需要等待。")
                Link("查看小组件与签名说明", destination: URL(string: "https://github.com/xiaozhangwangxue/HFUT-Schedule/blob/dev/docs/ios/1.2.1.md")!)
            }
        }
        .navigationTitle("桌面小组件")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            updateStatus()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) } catch { break }
                updateStatus()
            }
        }
    }

    private func statusText(_ status: WidgetPublicationStatus) -> String {
        if !status.didWrite { return "共享写入失败，请检查签名配置" }
        if acknowledged { return "小组件已读取本次课表" }
        if status.didWrite { return "已发送，等待小组件读取" }
        return "共享写入失败，请检查签名配置"
    }

    private func updateStatus() {
        publication = WidgetSnapshotStore.lastSyncStatus
        acknowledged = publication.map { $0.didWrite && WidgetSnapshotStore.acknowledged($0) } ?? false
    }
}
