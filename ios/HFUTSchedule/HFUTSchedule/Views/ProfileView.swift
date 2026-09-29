import SwiftUI

/// 选项页：结构与原版一致 —— 个人信息 / 更新版本 / 应用设置（外观、偏好与配置、网络、维护与关于）。
struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var scheduleStore: ScheduleStore
    @EnvironmentObject private var studentStore: AcademicStudentStore
    @State private var showingLogin = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                accountCard
                updateCard

                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "应用设置")
                    settingsList
                }
            }
            .padding(16)
            .padding(.bottom, 28)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("选项")
        .sheet(isPresented: $showingLogin) {
            NavigationStack { LoginPortalView() }
        }
        .onAppear { presentRequestedLogin() }
        .onChange(of: appState.shouldPresentLogin) { _, _ in presentRequestedLogin() }
    }

    // MARK: - 个人信息

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 15) {
                GlassIcon(systemName: "person.crop.circle.fill", tint: AppTheme.violet, size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(studentStore.info?.name.isEmpty == false ? studentStore.info!.name : "游客")
                        .font(.title3.weight(.bold))
                    Text(accountSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Text(termProgressText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    /// 学期进度：对应原版「已过 X%」。
    private var termProgressText: String {
        let courses = scheduleStore.courses
        guard let termStart = ScheduleCalendar.termStart(from: courses),
              let lastDate = courses.compactMap({ $0.dates?.compactMap { ScheduleCalendar.isoDate($0) }.max() }).max() else {
            return "第 \(currentWeek) 周"
        }
        let total = lastDate.timeIntervalSince(termStart)
        guard total > 0 else { return "第 \(currentWeek) 周" }
        let passed = Date().timeIntervalSince(termStart)
        if passed < 0 { return "未开学" }
        let percent = min(100, max(0, passed / total * 100))
        return String(format: "已过 %.1f%%", percent)
    }

    private var currentWeek: Int {
        ScheduleCalendar.currentWeek(termStart: ScheduleCalendar.termStart(from: scheduleStore.courses))
    }

    // MARK: - 更新版本

    private var updateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle")
                    .font(.title2)
                    .foregroundStyle(AppTheme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("当前版本 \(AppInfo.version)")
                        .font(.subheadline.weight(.semibold))
                    Text("已是最新版本，更新说明见项目 Releases")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            if let url = URL(string: "https://github.com/xiaozhangwangxue/HFUT-Schedule/releases") {
                Link(destination: url) {
                    Text("查看更新日志")
                        .font(.footnote)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaptiveGlass(cornerRadius: 22)
    }

    // MARK: - 应用设置

    private var settingsList: some View {
        VStack(spacing: 0) {
            SettingsNavigationRow(
                icon: "paintbrush.fill",
                title: "外观",
                subtitle: "色彩 动效 特效",
                tint: AppTheme.violet
            ) { AppearanceSettingsView() }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)

            Divider().padding(.leading, 56)

            SettingsNavigationRow(
                icon: "slider.horizontal.3",
                title: "偏好与配置",
                subtitle: "配置项 缓存清理",
                tint: AppTheme.cyan
            ) { PreferencesSettingsView() }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)

            Divider().padding(.leading, 56)

            SettingsNavigationRow(
                icon: "antenna.radiowaves.left.and.right",
                title: "网络",
                subtitle: "预加载 密码修改",
                tint: AppTheme.mint
            ) { NetworkSettingsView() }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)

            Divider().padding(.leading, 56)

            NavigationLink {
                AboutView()
            } label: {
                HStack(spacing: 12) {
                    SettingsIcon(systemName: "info.circle.fill", tint: .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("维护与关于").font(.subheadline.weight(.medium))
                        Text("反馈 关于 修复").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
        }
        .adaptiveGlass(cornerRadius: 22)
    }
}

enum AppInfo {
    static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }
}

private struct AboutView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                Label("聚在工大 iOS", systemImage: "app.badge.fill")
                LabeledContent("版本", value: AppInfo.version)
                LabeledContent("界面", value: "SwiftUI + Liquid Glass")
            }
            Section("维护") {
                Button {
                    openURL(URL(string: "https://github.com/xiaozhangwangxue/HFUT-Schedule/issues/new")!)
                } label: {
                    Label("提交反馈", systemImage: "bubble.left.and.exclamationmark.bubble.right")
                }
                Button {
                    openURL(URL(string: "https://github.com/xiaozhangwangxue/HFUT-Schedule")!)
                } label: {
                    Label("项目主页与更新", systemImage: "link")
                }
            }
            Section("开源") {
                Text("本项目基于原 Android 项目 Chiu-xaH/HFUT-Schedule 移植，遵循 Apache License 2.0。校方接口与数据均来自学校公开系统，仅供学习交流使用。")
                    .font(.footnote)
            }
        }
        .navigationTitle("维护与关于")
        .navigationBarTitleDisplayMode(.inline)
    }
}
