import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - 通用行组件

struct SettingsIcon: View {
    let systemName: String
    var tint: Color = AppTheme.accent

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 30, height: 30)
            .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

struct SettingsToggleRow: View {
    let icon: String
    let title: String
    var subtitle: String?
    var tint: Color = AppTheme.accent
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                SettingsIcon(systemName: icon, tint: tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.medium))
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct SettingsNavigationRow<Destination: View>: View {
    let icon: String
    let title: String
    var subtitle: String?
    var value: String?
    var tint: Color = AppTheme.accent
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 12) {
                SettingsIcon(systemName: icon, tint: tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.medium))
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if let value {
                    Text(value).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - 外观

struct AppearanceSettingsView: View {
    @AppStorage(AppSettingsKey.appearance) private var appearance = AppAppearance.auto.rawValue
    @AppStorage(AppSettingsKey.pureBlack) private var pureBlack = false
    @AppStorage(AppSettingsKey.webDarkMode) private var webDarkMode = false
    @AppStorage(AppSettingsKey.accentHex) private var accentHex = ""
    @AppStorage(AppSettingsKey.accentSaturation) private var saturation = 1.0
    @AppStorage(AppSettingsKey.liquidGlass) private var liquidGlass = true
    @AppStorage(AppSettingsKey.showTeacherInSquare) private var showTeacher = false
    @AppStorage(AppSettingsKey.mergeConflictingSquares) private var mergeConflicts = false
    @AppStorage(AppSettingsKey.backgroundBlur) private var backgroundBlur = 0.35
    @AppStorage(AppSettingsKey.showAllTabLabels) private var showAllTabLabels = true
    @State private var backgroundItem: PhotosPickerItem?
    @State private var customColor = Color.blue

    private var backgroundColor: Binding<Color> {
        Binding(
            get: { accentHex.isEmpty ? AppTheme.defaultAccent : Color(hex: accentHex) ?? AppTheme.defaultAccent },
            set: { newValue in
                accentHex = newValue.hexString ?? ""
                AppTheme.applyAccent(hex: accentHex, saturation: saturation)
            }
        )
    }

    var body: some View {
        List {
            Section("深浅色") {
                Picker("深浅色", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                SettingsToggleRow(icon: "moon.fill", title: "纯黑深色背景",
                                  subtitle: "OLED 屏在深色模式时使用不发光的纯黑背景",
                                  tint: .purple, isOn: $pureBlack)
                SettingsToggleRow(icon: "globe.desk.fill", title: "强制网页深色模式",
                                  subtitle: "给校内网页注入深色样式，显示异常时可关闭",
                                  tint: .indigo, isOn: $webDarkMode)
            }

            Section("主题色") {
                HStack {
                    SettingsIcon(systemName: "paintpalette.fill")
                    Text("自定义取色").font(.subheadline.weight(.medium))
                    Spacer()
                    ColorPicker("", selection: backgroundColor, supportsOpacity: false)
                        .labelsHidden()
                }
                HStack {
                    SettingsIcon(systemName: "sun.max.fill", tint: .orange)
                    Text("鲜艳度").font(.subheadline.weight(.medium))
                    Slider(value: $saturation, in: 0.6...1.4, step: 0.05)
                        .onChange(of: saturation) { _, value in
                            AppTheme.applyAccent(hex: accentHex, saturation: value)
                        }
                    Text(String(format: "%.0f%%", saturation * 100))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("恢复默认主题色") {
                    accentHex = ""
                    saturation = 1.0
                    AppTheme.applyAccent(hex: "", saturation: 1)
                }
                .font(.subheadline)
            }

            Section("特效") {
                SettingsToggleRow(icon: "cube.transparent.fill", title: "液态玻璃",
                                  subtitle: "使用系统材质实现毛玻璃与层级模糊",
                                  tint: AppTheme.cyan, isOn: $liquidGlass)
                Text("动效与透明度会自动跟随系统的「减弱动态效果」「降低透明度」设置。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("课程表") {
                SettingsToggleRow(icon: "person.fill", title: "方格内显示教师",
                                  subtitle: "在课程方格中显示授课教师",
                                  tint: AppTheme.violet, isOn: $showTeacher)
                SettingsToggleRow(icon: "rectangle.stack.fill", title: "合并冲突方格",
                                  subtitle: "同一时间段的课程合并显示",
                                  tint: .teal, isOn: $mergeConflicts)
                PhotosPicker(selection: $backgroundItem, matching: .images) {
                    HStack(spacing: 12) {
                        SettingsIcon(systemName: "photo.fill", tint: .pink)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("课程表背景").font(.subheadline.weight(.medium))
                            Text("选择一张图片作为课表背景").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                    }
                }
                if TimetableBackgroundStore.hasBackground {
                    HStack {
                        SettingsIcon(systemName: "drop.fill", tint: .pink)
                        Text("前景模糊").font(.subheadline.weight(.medium))
                        Slider(value: $backgroundBlur, in: 0...1, step: 0.05)
                        Text("\(Int(backgroundBlur * 100))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("移除背景", role: .destructive) {
                        TimetableBackgroundStore.clear()
                    }
                    .font(.subheadline)
                }
            }

            Section("底栏") {
                SettingsToggleRow(icon: "dock.rectangle", title: "显示所有底栏标签",
                                  subtitle: "显示全部标签或仅显示选中项",
                                  tint: .brown, isOn: $showAllTabLabels)
            }
        }
        .navigationTitle("外观")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            customColor = backgroundColor.wrappedValue
        }
        .onChange(of: backgroundItem) { _, item in
            guard let item else { return }
            Task { await saveBackground(item) }
        }
    }

    @MainActor
    private func saveBackground(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        TimetableBackgroundStore.save(data)
    }
}

// MARK: - 偏好与配置

struct PreferencesSettingsView: View {
    @EnvironmentObject private var scheduleStore: ScheduleStore
    @EnvironmentObject private var notificationManager: CourseNotificationManager
    @EnvironmentObject private var appState: AppState

    @AppStorage(AppSettingsKey.defaultCourseSource) private var courseSource = DefaultCourseSource.academic.rawValue
    @AppStorage(AppSettingsKey.autoTermStart) private var autoTermStart = true
    @AppStorage(AppSettingsKey.manualTermStart) private var manualTermStart = 0.0
    @AppStorage(AppSettingsKey.showFinishedToday) private var showFinishedToday = true
    @AppStorage(AppSettingsKey.showExpiredEvents) private var showExpiredEvents = false
    @AppStorage(AppSettingsKey.xuanchengQuota) private var xuanchengQuota = 30.0
    @AppStorage(AppSettingsKey.ignoreExcludedGrades) private var ignoreExcludedGrades = false
    @State private var exportingBackup = false
    @State private var importingBackup = false
    @State private var message: String?
    @State private var cacheSize = "—"

    private var manualTermBinding: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: manualTermStart > 0 ? manualTermStart : Date().timeIntervalSince1970) },
            set: { manualTermStart = $0.timeIntervalSince1970 }
        )
    }

    var body: some View {
        List {
            Section("交互") {
                Toggle(isOn: $appState.prefersHaptics) {
                    HStack(spacing: 12) {
                        SettingsIcon(systemName: "waveform", tint: AppTheme.cyan)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("触感反馈").font(.subheadline.weight(.medium))
                            Text("在关键操作完成时反馈").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("课程表") {
                Picker("默认课程表", selection: $courseSource) {
                    ForEach(DefaultCourseSource.allCases) { source in
                        Text(source.title).tag(source.rawValue)
                    }
                }
                if let source = DefaultCourseSource(rawValue: courseSource) {
                    Text(source.detail).font(.caption).foregroundStyle(.secondary)
                }
                LabeledContent("当前学期", value: "第 \(currentWeek) 周 · \(AcademicPortal.currentSemesterID)")
                Toggle(isOn: $autoTermStart) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("自动计算学期").font(.subheadline.weight(.medium))
                        Text("按日期自动判断学期；关闭后可手动指定学期开始时间")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !autoTermStart {
                    DatePicker("学期开始时间", selection: manualTermBinding, displayedComponents: .date)
                        .onChange(of: manualTermStart) { _, value in
                            UserDefaults.standard.set(value, forKey: AppSettingsKey.manualTermStart)
                        }
                }
            }

            Section("偏好与配置") {
                Toggle(isOn: $showFinishedToday) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("聚焦仍显示今天已完成的项目").font(.subheadline.weight(.medium))
                        Text("显示或隐藏今天上完的课程").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $showExpiredEvents) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("聚焦中仍显示已结束的日程").font(.subheadline.weight(.medium))
                        Text("显示或隐藏已过期的自建日程").font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    SettingsIcon(systemName: "wifi", tint: AppTheme.mint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("宣城校区校园网月免费额度").font(.subheadline.weight(.medium))
                        Text("用于计算和显示使用百分比").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(Int(xuanchengQuota)) GiB").foregroundStyle(.secondary)
                }
                Slider(value: $xuanchengQuota, in: 5...100, step: 5)

                Toggle(isOn: $ignoreExcludedGrades) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("忽略平均成绩的排除计算").font(.subheadline.weight(.medium))
                        Text("允许被排除的成绩项目参与计算，可能会拉低原平均成绩")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Section("通知") {
                SettingsToggleRow(icon: "bell.badge.fill", title: "课程提醒",
                                  subtitle: "上课前 \(notificationManager.leadMinutes) 分钟提醒",
                                  tint: .orange, isOn: reminderBinding)
                if notificationManager.isEnabled {
                    Picker("提前时间", selection: reminderLeadBinding) {
                        ForEach([5, 10, 15, 30, 60], id: \.self) { minutes in
                            Text("\(minutes) 分钟").tag(minutes)
                        }
                    }
                }
            }

            Section("存储") {
                Button {
                    exportingBackup = true
                } label: {
                    Label("导出课表备份", systemImage: "square.and.arrow.up")
                }
                Button {
                    importingBackup = true
                } label: {
                    Label("恢复课表备份", systemImage: "square.and.arrow.down")
                }
                Button {
                    clearCache()
                } label: {
                    HStack {
                        Label("缓存清理", systemImage: "trash")
                        Spacer()
                        Text(cacheSize).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("偏好与配置")
        .navigationBarTitleDisplayMode(.inline)
        .task { cacheSize = Self.cacheSizeText() }
        .fileExporter(
            isPresented: $exportingBackup,
            document: ScheduleBackupDocument(courses: scheduleStore.courses),
            contentType: .json,
            defaultFilename: "聚在工大课表备份"
        ) { result in
            if case .failure(let error) = result { message = error.localizedDescription }
        }
        .fileImporter(isPresented: $importingBackup, allowedContentTypes: [.json]) { result in
            importBackup(result)
        }
        .alert("提示", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("好") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private var currentWeek: Int {
        ScheduleCalendar.currentWeek(termStart: ScheduleCalendar.termStart(from: scheduleStore.courses))
    }

    private var reminderBinding: Binding<Bool> {
        Binding(
            get: { notificationManager.isEnabled },
            set: { enabled in
                notificationManager.isEnabled = enabled
                Task { try? await notificationManager.reschedule(for: scheduleStore.courses) }
            }
        )
    }

    private var reminderLeadBinding: Binding<Int> {
        Binding(
            get: { notificationManager.leadMinutes },
            set: { minutes in
                notificationManager.leadMinutes = minutes
                Task { try? await notificationManager.reschedule(for: scheduleStore.courses) }
            }
        )
    }

    private func clearCache() {
        URLCache.shared.removeAllCachedResponses()
        cacheSize = Self.cacheSizeText()
        message = "已清理缓存"
    }

    private static func cacheSizeText() -> String {
        let bytes = URLCache.shared.currentDiskUsage + URLCache.shared.currentMemoryUsage
        return String(format: "%.2f MB", Double(bytes) / 1_048_576)
    }

    private func importBackup(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let granted = url.startAccessingSecurityScopedResource()
            defer { if granted { url.stopAccessingSecurityScopedResource() } }
            let courses = try JSONDecoder().decode([Course].self, from: Data(contentsOf: url))
            scheduleStore.replace(with: courses)
            Task { try? await notificationManager.reschedule(for: courses) }
            message = "已恢复 \(courses.count) 门课程。"
        } catch {
            message = "恢复失败：\(error.localizedDescription)"
        }
    }
}

// MARK: - 网络

struct NetworkSettingsView: View {
    @EnvironmentObject private var studentStore: AcademicStudentStore
    @AppStorage(AppSettingsKey.useDefaultCardPassword) private var useDefaultCardPassword = true
    @AppStorage(AppSettingsKey.autoRefreshLogin) private var autoRefreshLogin = false
    @AppStorage(AppSettingsKey.dataReporting) private var dataReporting = true
    @AppStorage(AppSettingsKey.pageSize) private var pageSize = 30

    @State private var cardPassword = AppSecretStore.read(AppSecretStore.Account.cardPassword) ?? ""
    @State private var schoolNetPassword = AppSecretStore.read(AppSecretStore.Account.schoolNetPassword) ?? ""
    @State private var academicPassword = AppSecretStore.read(AppSecretStore.Account.academicPassword) ?? ""
    @State private var aiKey = AppSecretStore.read(AppSecretStore.Account.aiAPIKey) ?? ""
    @State private var editing: EditingField?
    @State private var message: String?
    @State private var isRefreshingLogin = false

    private enum EditingField: String, Identifiable {
        case card, schoolNet, academic, ai
        var id: String { rawValue }
        var title: String {
            switch self {
            case .card: "一卡通密码"
            case .schoolNet: "校园网密码"
            case .academic: "教务系统密码"
            case .ai: "大模型 ApiKey"
            }
        }
    }

    private var isXuancheng: Bool { studentStore.info?.campus.contains("宣城") == true }
    private var identityTail: String {
        AppSecretStore.defaultPassword(fromIdentity: studentStore.info?.fields["身份证号"] ?? studentStore.info?.fields["证件号"])
            ?? "证件号后 6 位"
    }

    var body: some View {
        List {
            Section("配置") {
                Button {
                    editing = .card
                } label: {
                    HStack(spacing: 12) {
                        SettingsIcon(systemName: "creditcard.fill", tint: AppTheme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isXuancheng ? "一卡通及校园网密码" : "一卡通密码")
                                .font(.subheadline.weight(.medium))
                            Text("修改过初始密码后在此录入，用于快速充值\(isXuancheng ? "与校园网登录" : "")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(cardPassword.isEmpty ? "未设置" : "已设置")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !isXuancheng {
                    Toggle(isOn: $useDefaultCardPassword) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("使用合肥校区默认密码").font(.subheadline.weight(.medium))
                            Text("默认密码为 \(identityTail)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        editing = .schoolNet
                    } label: {
                        HStack(spacing: 12) {
                            SettingsIcon(systemName: "wifi", tint: AppTheme.mint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("校园网密码").font(.subheadline.weight(.medium))
                                Text("用于校园网一键登录").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(schoolNetPassword.isEmpty ? "未设置" : "已设置")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Button {
                    editing = .academic
                } label: {
                    HStack(spacing: 12) {
                        SettingsIcon(systemName: "graduationcap.fill", tint: AppTheme.violet)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("教务系统密码").font(.subheadline.weight(.medium))
                            Text("修改过初始密码后在此录入，用于同班同学、教室、培养方案")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(academicPassword.isEmpty ? "默认密码" : "已设置")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                SettingsToggleRow(icon: "arrow.clockwise.circle.fill", title: "自动刷新登录状态",
                                  subtitle: "冷启动后自动在后台完成一次统一身份认证",
                                  tint: AppTheme.cyan, isOn: $autoRefreshLogin)
                Button {
                    editing = .ai
                } label: {
                    HStack(spacing: 12) {
                        SettingsIcon(systemName: "sparkles", tint: .purple)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("大模型").font(.subheadline.weight(.medium))
                            Text("填写 ApiKey 后可使用 AI 助手能力").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(aiKey.isEmpty ? "未设置" : "已设置").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Section("其它") {
                SettingsToggleRow(icon: "chart.bar.doc.horizontal.fill", title: "数据上报",
                                  subtitle: "允许上传崩溃日志等非敏感数据，帮助改进体验",
                                  tint: .orange, isOn: $dataReporting)
                Button {
                    Task { await refreshLogin() }
                } label: {
                    HStack(spacing: 12) {
                        SettingsIcon(systemName: "arrow.triangle.2.circlepath", tint: AppTheme.mint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("刷新登录状态").font(.subheadline.weight(.medium))
                            Text("一卡通或成绩无法查询时，重新登录一次")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if isRefreshingLogin { ProgressView().controlSize(.small) }
                    }
                }
                Stepper(value: $pageSize, in: 10...100, step: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("请求范围 | \(pageSize) 条/页").font(.subheadline.weight(.medium))
                        Text("一次加载的条目数，越大加载越慢但显示更多")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("网络")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { field in
            SecretEditorSheet(
                title: field.title,
                placeholder: field == .card ? "6 位数字" : "请输入密码",
                initial: initialValue(for: field),
                onSave: { value in save(value, for: field) }
            )
        }
        .alert("提示", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("好") { message = nil }
        } message: {
            Text(message ?? "")
        }
        .onAppear {
            // 修复「录入完成后二次弹出输入密码弹窗」的同类问题：打开时统一收敛编辑状态
            editing = nil
        }
    }

    private func initialValue(for field: EditingField) -> String {
        switch field {
        case .card: cardPassword
        case .schoolNet: schoolNetPassword
        case .academic: academicPassword
        case .ai: aiKey
        }
    }

    private func save(_ value: String, for field: EditingField) {
        switch field {
        case .card:
            cardPassword = value
            AppSecretStore.write(value, account: AppSecretStore.Account.cardPassword)
        case .schoolNet:
            schoolNetPassword = value
            AppSecretStore.write(value, account: AppSecretStore.Account.schoolNetPassword)
        case .academic:
            academicPassword = value
            AppSecretStore.write(value, account: AppSecretStore.Account.academicPassword)
        case .ai:
            aiKey = value
            AppSecretStore.write(value, account: AppSecretStore.Account.aiAPIKey)
        }
        editing = nil
        message = "已保存"
    }

    @MainActor
    private func refreshLogin() async {
        isRefreshingLogin = true
        defer { isRefreshingLogin = false }
        do {
            _ = try await CampusServiceClient.shared.refreshOnePortalToken()
            message = "登录状态已刷新"
        } catch {
            message = "刷新失败：\(error.localizedDescription)"
        }
    }
}

struct SecretEditorSheet: View {
    let title: String
    let placeholder: String
    let initial: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var value = ""

    var body: some View {
        NavigationStack {
            Form {
                SecureField(placeholder, text: $value)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text("留空表示清除已保存的密码。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        onSave(value)
                        dismiss()
                    }
                }
            }
            .onAppear { value = initial }
        }
    }
}

// MARK: - 课表背景存储

/// 设置项搜索（对应上游 SettingsSearchDestination）。
struct SettingsSearchView: View {
    struct Entry: Identifiable, Hashable {
        enum Target: String, Hashable {
            case appearance, preferences, network, about
            var title: String {
                switch self {
                case .appearance: "外观"
                case .preferences: "偏好与配置"
                case .network: "网络"
                case .about: "维护与关于"
                }
            }
        }

        let title: String
        let detail: String
        let target: Target
        var id: String { "\(target.rawValue)-\(title)" }
    }

    @State private var query = ""

    private static let allEntries: [Entry] = [
        Entry(title: "深浅色", detail: "跟随系统 / 浅色 / 深色", target: .appearance),
        Entry(title: "纯黑深色背景", detail: "OLED 深色模式纯黑背景", target: .appearance),
        Entry(title: "强制网页深色模式", detail: "给校内网页注入深色样式", target: .appearance),
        Entry(title: "主题色", detail: "自定义取色与鲜艳度", target: .appearance),
        Entry(title: "液态玻璃", detail: "系统材质与模糊", target: .appearance),
        Entry(title: "方格内显示教师", detail: "课程表显示授课教师", target: .appearance),
        Entry(title: "合并冲突方格", detail: "同一时间段的课程合并", target: .appearance),
        Entry(title: "课程表背景", detail: "背景图与前景模糊", target: .appearance),
        Entry(title: "显示所有底栏标签", detail: "底栏标签显示方式", target: .appearance),
        Entry(title: "触感反馈", detail: "关键操作震动反馈", target: .preferences),
        Entry(title: "默认课程表", detail: "合工大教务 / 智慧社区", target: .preferences),
        Entry(title: "自动计算学期", detail: "按日期判断学期", target: .preferences),
        Entry(title: "学期开始时间", detail: "自定义学期开始时间", target: .preferences),
        Entry(title: "聚焦仍显示今天已完成的项目", detail: "上完的课程是否显示", target: .preferences),
        Entry(title: "聚焦中仍显示已结束的日程", detail: "过期日程是否显示", target: .preferences),
        Entry(title: "宣城校区校园网月免费额度", detail: "用于计算使用百分比", target: .preferences),
        Entry(title: "忽略平均成绩的排除计算", detail: "让被排除的成绩参与平均分", target: .preferences),
        Entry(title: "课程提醒", detail: "上课前提醒", target: .preferences),
        Entry(title: "备份与恢复", detail: "导出、恢复课表备份", target: .preferences),
        Entry(title: "缓存清理", detail: "清理缓存不影响数据", target: .preferences),
        Entry(title: "一卡通密码", detail: "快速充值与校园网登录", target: .network),
        Entry(title: "校园网密码", detail: "校园网一键登录", target: .network),
        Entry(title: "教务系统密码", detail: "同班同学、教室、培养方案", target: .network),
        Entry(title: "自动刷新登录状态", detail: "冷启动后台统一认证", target: .network),
        Entry(title: "大模型", detail: "填写 ApiKey", target: .network),
        Entry(title: "数据上报", detail: "崩溃日志上报", target: .network),
        Entry(title: "刷新登录状态", detail: "重新登录一次", target: .network),
        Entry(title: "请求范围", detail: "一次加载的条目数", target: .network),
        Entry(title: "版本与开源许可", detail: "当前版本、反馈、开源协议", target: .about)
    ]

    private var filtered: [Entry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return Self.allEntries }
        return Self.allEntries.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
                || $0.detail.localizedCaseInsensitiveContains(trimmed)
                || $0.target.title.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        List {
            ForEach(filtered) { entry in
                NavigationLink {
                    destination(for: entry.target)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.title).font(.subheadline.weight(.medium))
                        Text("\(entry.target.title) · \(entry.detail)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if filtered.isEmpty {
                Text("没有匹配的设置项。").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .searchable(text: $query, prompt: "搜索设置项")
        .navigationTitle("搜索设置项")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func destination(for target: Entry.Target) -> some View {
        switch target {
        case .appearance: AppearanceSettingsView()
        case .preferences: PreferencesSettingsView()
        case .network: NetworkSettingsView()
        case .about:
            List {
                Section {
                    LabeledContent("版本", value: AppInfo.version)
                    LabeledContent("界面", value: "SwiftUI + Liquid Glass")
                }
                Section("开源") {
                    Text("本项目基于原 Android 项目 Chiu-xaH/HFUT-Schedule 移植，遵循 Apache License 2.0。")
                        .font(.footnote)
                }
            }
            .navigationTitle("维护与关于")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

enum TimetableBackgroundStore {
    static var fileURL: URL? {
        guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let folder = directory.appendingPathComponent("HFUTSchedule", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("timetable-background.jpg")
    }

    static var hasBackground: Bool {
        guard let fileURL else { return false }
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    static func save(_ data: Data) {
        guard let fileURL else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func clear() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
