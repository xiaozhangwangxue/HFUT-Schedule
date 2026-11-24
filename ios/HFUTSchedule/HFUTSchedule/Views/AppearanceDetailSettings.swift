import SwiftUI

struct TimetableAppearanceSettingsView: View {
    @AppStorage(AppSettingsKey.calendarHourHeight) private var height = 68.0
    @AppStorage(AppSettingsKey.calendarTextScale) private var textScale = 1.0
    @AppStorage(AppSettingsKey.calendarPadding) private var padding = 3.0
    @AppStorage(AppSettingsKey.calendarOpacity) private var opacity = 0.38
    @AppStorage(AppSettingsKey.teacherDisplayMode) private var teacherMode = 0
    var body: some View {
        Form {
            Section("方格") {
                valueSlider("每小时高度", value: $height, range: 40...140, step: 1, unit: "点")
                valueSlider("文字大小", value: $textScale, range: 0.6...1.8, step: 0.05, multiplier: 100, unit: "%")
                valueSlider("内容边距", value: $padding, range: 0...12, step: 0.5, unit: "点")
                valueSlider("色块不透明度", value: $opacity, range: 0.1...1, step: 0.05, multiplier: 100, unit: "%")
                Picker("显示教师", selection: $teacherMode) {
                    Text("不显示").tag(0); Text("仅多名教师时").tag(1); Text("始终显示").tag(2)
                }
            }
            Section {
                Button("恢复方格默认值") { height = 68; textScale = 1; padding = 3; opacity = 0.38; teacherMode = 0 }
            } footer: { Text("课表中的双指缩放也会改变每小时高度。") }
        }
        .navigationTitle("课表方格")
        .task { AppSettingsKey.migrateLegacyPreferences() }
    }
    private func valueSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double,
                             multiplier: Double = 1, unit: String) -> some View {
        VStack(alignment: .leading) {
            HStack { Text(title); Spacer(); Text("\(Int((value.wrappedValue * multiplier).rounded())) \(unit)").foregroundStyle(.secondary) }
            Slider(value: value, in: range, step: step)
        }
    }
}

struct MotionAppearanceSettingsView: View {
    @AppStorage(AppSettingsKey.layerBlur) private var layerBlur = true
    @AppStorage(AppSettingsKey.transitionLevel) private var level = 1
    @AppStorage(AppSettingsKey.transitionSpeed) private var speed = 1.0
    @AppStorage(AppSettingsKey.transitionEffect) private var effect = "default"
    @AppStorage(AppSettingsKey.sharedContainer) private var shared = true
    @AppStorage(AppSettingsKey.containerClips) private var clips = false
    @State private var previewID = UUID()
    var body: some View {
        Form {
            Section("材质") { Toggle("层级模糊", isOn: $layerBlur) }
            Section {
                Picker("动效级别", selection: $level) { Text("关闭").tag(0); Text("轻柔").tag(1); Text("完整").tag(2) }
                Picker("默认效果", selection: $effect) { Text("淡入").tag("default"); Text("缩放").tag("scale"); Text("推入").tag("push") }
                HStack { Text("动画速率"); Slider(value: $speed, in: 0.25...3, step: 0.25); Text(String(format: "%.2f×", speed)).monospacedDigit().font(.caption) }
                Toggle("从来源控件展开", isOn: $shared)
                Toggle("裁切容器过渡", isOn: $clips)
            } header: { Text("转场") } footer: { Text("系统「减弱动态效果」优先。来源展开与交互返回遵循 iOS 系统转场；速率控制页面内容的进入动画。") }
            Section("预览") {
                RoundedRectangle(cornerRadius: 16).fill(AppTheme.accent.gradient).frame(height: 80)
                    .configuredPageTransition().id(previewID)
                Button("重播当前效果") { previewID = UUID() }
                SourceAnchoredNavigationLink(sourceID: "appearance-transition-preview") {
                    Text("返回可查看收拢效果").frame(maxWidth: .infinity, maxHeight: .infinity).background(AppTheme.background)
                } label: { Label("预览页面转场", systemImage: "arrow.up.left.and.arrow.down.right") }
            }
        }.navigationTitle("材质与动效")
    }
}
