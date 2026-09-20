import SwiftUI
import UniformTypeIdentifiers

struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var scheduleStore: ScheduleStore
    @EnvironmentObject private var notificationManager: CourseNotificationManager
    @EnvironmentObject private var studentStore: AcademicStudentStore
    @State private var showingLogin = false
    @State private var showingAbout = false
    @State private var exportingBackup = false
    @State private var importingBackup = false
    @State private var backupMessage: String?
    @AppStorage("timetableShowsTimeLine") private var timetableShowsTimeLine = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                accountCard

                VStack(spacing: 10) {
                    SectionHeader(title: "偏好与配置")
                    settingsCard
                }

                VStack(spacing: 10) {
                    SectionHeader(title: "关于")
                    Button {
                        showingAbout = true
                    } label: {
                        settingsRow(icon: "info.circle.fill", title: "版本与开源许可", value: "0.1.0")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .padding(.bottom, 28)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("我的")
        .sheet(isPresented: $showingLogin) {
            NavigationStack { LoginPortalView() }
        }
        .sheet(isPresented: $showingAbout) {
            AboutView()
        }
        .fileExporter(
            isPresented: $exportingBackup,
            document: ScheduleBackupDocument(courses: scheduleStore.courses),
            contentType: .json,
            defaultFilename: "聚在工大课表备份"
        ) { result in
            if case .failure(let error) = result { backupMessage = error.localizedDescription }
        }
        .fileImporter(isPresented: $importingBackup, allowedContentTypes: [.json]) { result in
            importBackup(result)
        }
        .alert("数据备份", isPresented: Binding(
            get: { backupMessage != nil },
            set: { if !$0 { backupMessage = nil } }
        )) {
            Button("好") { backupMessage = nil }
        } message: {
            Text(backupMessage ?? "")
        }
        .task { await notificationManager.refresh() }
        .onAppear { presentRequestedLogin() }
        .onChange(of: appState.shouldPresentLogin) { _, _ in presentRequestedLogin() }
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 15) {
                GlassIcon(systemName: "person.crop.circle.fill", tint: AppTheme.violet, size: 60)
                VStack(alignment: .leading, spacing: 4) {
                    Text(studentStore.info?.name.isEmpty == false ? studentStore.info!.name : "统一身份认证")
                        .font(.title3.weight(.bold))
                    Text(accountSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Button("前往安全登录", systemImage: "lock.shield.fill") {
                showingLogin = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
        }
        .padding(20)
        .adaptiveGlass(cornerRadius: 26)
    }

    private func presentRequestedLogin() {
        if appState.consumeLoginRequest() { showingLogin = true }
    }

    private var accountSubtitle: String {
        guard let info = studentStore.info else { return "登录后自动同步学籍、课表、成绩与考试" }
        return [info.studentID, info.department, info.major, info.className]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var settingsCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                GlassIcon(systemName: "location.fill", tint: AppTheme.mint)
                Text("校区")
                    .font(.headline)
                Spacer()
                Picker("校区", selection: $appState.campus) {
                    ForEach(AppState.Campus.allCases) { campus in
                        Text(campus.rawValue).tag(campus)
                    }
                }
                .labelsHidden()
            }
            .padding(14)

            Divider().padding(.leading, 70)

            Toggle(isOn: $appState.prefersHaptics) {
                HStack(spacing: 14) {
                    GlassIcon(systemName: "waveform", tint: AppTheme.cyan)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("触感反馈")
                            .font(.headline)
                        Text("在关键操作完成时反馈")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(14)

            Divider().padding(.leading, 70)

            Toggle(isOn: $timetableShowsTimeLine) {
                HStack(spacing: 14) {
                    GlassIcon(systemName: "calendar.day.timeline.left", tint: .red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("课表时间线")
                            .font(.headline)
                        Text("在当前周今天的课程格里显示当前时间线")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(14)

            Divider().padding(.leading, 70)

            Toggle(isOn: reminderBinding) {
                HStack(spacing: 14) {
                    GlassIcon(systemName: "bell.badge.fill", tint: .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("课程提醒")
                            .font(.headline)
                        Text("上课前 \(notificationManager.leadMinutes) 分钟提醒")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(14)

            if notificationManager.isEnabled {
                Picker("提前时间", selection: reminderLeadBinding) {
                    ForEach([5, 10, 15, 30, 60], id: \.self) { minutes in
                        Text("\(minutes) 分钟").tag(minutes)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }

            Divider().padding(.leading, 70)

            Button {
                exportingBackup = true
            } label: {
                actionRow(icon: "square.and.arrow.up.fill", title: "导出课表备份")
            }
            .buttonStyle(.plain)

            Divider().padding(.leading, 70)

            Button {
                importingBackup = true
            } label: {
                actionRow(icon: "square.and.arrow.down.fill", title: "恢复课表备份")
            }
            .buttonStyle(.plain)

            Divider().padding(.leading, 70)

            HStack(spacing: 14) {
                GlassIcon(systemName: "accessibility", tint: .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("辅助功能")
                        .font(.headline)
                    Text("自动跟随系统的动态字体、减少动态与减少透明度设置")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
        }
        .adaptiveGlass(cornerRadius: 24)
    }

    private var reminderBinding: Binding<Bool> {
        Binding(
            get: { notificationManager.isEnabled },
            set: { enabled in
                notificationManager.isEnabled = enabled
                Task {
                    do {
                        try await notificationManager.reschedule(for: scheduleStore.courses)
                    } catch {
                        backupMessage = error.localizedDescription
                    }
                }
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

    private func actionRow(icon: String, title: String) -> some View {
        HStack(spacing: 14) {
            GlassIcon(systemName: icon, tint: AppTheme.cyan)
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .contentShape(Rectangle())
    }

    private func importBackup(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessGranted = url.startAccessingSecurityScopedResource()
            defer { if accessGranted { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let courses = try JSONDecoder().decode([Course].self, from: data)
            scheduleStore.replace(with: courses)
            Task { try? await notificationManager.reschedule(for: courses) }
            backupMessage = "已恢复 \(courses.count) 门课程。"
        } catch {
            backupMessage = "恢复失败：\(error.localizedDescription)"
        }
    }

    private func settingsRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 14) {
            GlassIcon(systemName: icon, tint: AppTheme.violet)
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .adaptiveGlass(cornerRadius: 22, interactive: true)
    }
}

private struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("聚在工大 iOS", systemImage: "app.badge.fill")
                    LabeledContent("版本", value: "0.1.0 (1)")
                    LabeledContent("界面", value: "SwiftUI + Liquid Glass")
                }
                Section("开源") {
                    Text("本移植基于 Chiu-xaH/HFUT-Schedule，遵循 Apache License 2.0。修改文件保留变更说明与来源归属。")
                    Link("查看上游仓库", destination: URL(string: "https://github.com/Chiu-xaH/HFUT-Schedule")!)
                }
                Section("隐私") {
                    Text("登录凭据仅发送到合肥工业大学官方 CAS 与教务接口；应用不保存密码。校方返回的短期令牌保存在本机系统钥匙串中。")
                }
            }
            .navigationTitle("关于")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
