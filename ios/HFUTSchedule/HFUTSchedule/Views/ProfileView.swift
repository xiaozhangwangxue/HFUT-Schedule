import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showingLogin = false
    @State private var showingAbout = false

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
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 15) {
                GlassIcon(systemName: "person.crop.circle.fill", tint: AppTheme.violet, size: 60)
                VStack(alignment: .leading, spacing: 4) {
                    Text("统一身份认证")
                        .font(.title3.weight(.bold))
                    Text("登录后访问教务、图书馆与校园服务")
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
                    Text("校园登录在校方网页中完成。网页会话由系统 WebKit 数据存储管理；应用不读取或记录登录密码。")
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
