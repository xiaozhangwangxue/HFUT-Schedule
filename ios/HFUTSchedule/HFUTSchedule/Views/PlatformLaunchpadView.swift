import SwiftUI

/// Root supplies entries from its actual NavigationPath. An entry's ID is the
/// return token; selecting one asks Root to remove the later path elements.
struct PlatformNavigationEntry: Identifiable, Equatable {
    let id: UUID
    let title: String
    init(id: UUID = UUID(), title: String) { self.id = id; self.title = title }
}

struct PlatformLaunchpadView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettingsKey.appearance) private var appearance = AppAppearance.auto.rawValue
    @AppStorage(AppSettingsKey.pureBlack) private var pureBlack = false
    @AppStorage(AppSettingsKey.accentSaturation) private var saturation = 1.0
    @State private var returnScope: String
    @State private var returnHistory: [PlatformNavigationEntry]
    init() {
        let coordinator = PlatformNavigationCoordinator.shared
        _returnScope = State(initialValue: coordinator.activeScope)
        _returnHistory = State(initialValue: coordinator.history(forScope: coordinator.activeScope))
    }
    var body: some View {
        List {
            Section("返回页面") {
                if returnHistory.isEmpty {
                    Text("当前页没有可返回的子页面。") .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(returnHistory.enumerated()), id: \.element.id) { index, entry in
                        Button {
                            PlatformNavigationCoordinator.shared.returnTo(entry.id, in: returnScope)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: index == 0 ? "house" : "arrow.turn.up.left")
                                Text(entry.title)
                                Spacer()
                                if index == returnHistory.count - 1 { Text("当前").font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
            }
            Section("外观快捷设置") {
                Picker("外观", selection: $appearance) { ForEach(AppAppearance.allCases) { Text($0.title).tag($0.rawValue) } }
                Toggle("深色使用纯黑背景", isOn: $pureBlack)
                LabeledContent("主题鲜艳度", value: "\(Int(saturation * 100))%")
                Slider(value: $saturation, in: 0...1, step: 0.05)
                AppNavigationLink("完整外观设置") { AppearanceSettingsView() }
            }
            Section {
                AppNavigationLink("快捷入口编辑") { PlatformShortcutsView() }
                AppNavigationLink("系统日历") { CalendarIntegrationView() }
                AppNavigationLink("聚焦组件与实时活动") { PlatformWidgetsSettingsView() }
                AppNavigationLink("错误详情") { PlatformDiagnosticsView() }
            }
        }.navigationTitle("启动台").toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
    }
}
