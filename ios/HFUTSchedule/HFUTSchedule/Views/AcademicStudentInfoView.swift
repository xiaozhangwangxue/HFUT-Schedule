import SwiftUI
import UIKit

struct AcademicStudentInfoView: View {
    @EnvironmentObject private var studentStore: AcademicStudentStore
    @AppStorage("studentInfoShowsSensitiveFields") private var showsSensitive = false
    @State private var showingLogin = false
    @State private var photo: UIImage?
    @State private var photoError: String?

    var body: some View {
        Group {
            if let info = studentStore.info {
                List {
                    Section {
                        if let error = studentStore.error { Text(error).font(.footnote).foregroundStyle(.red) }
                        Button("刷新个人信息", systemImage: "arrow.clockwise") { Task { await studentStore.refresh(force: true) } }.disabled(studentStore.loading)
                        Button("重新登录教务系统", systemImage: "lock.shield") { showingLogin = true }
                        HStack(spacing: 14) {
                            if let photo {
                                Image(uiImage: photo).resizable().scaledToFill().frame(width: 56, height: 72).clipShape(RoundedRectangle(cornerRadius: 9))
                            } else {
                                GlassIcon(systemName: "person.crop.circle.fill", tint: AppTheme.violet, size: 56)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(info.name.isEmpty ? "在校生" : info.name)
                                    .font(.title3.bold())
                                Button { UIPasteboard.general.string = info.studentID } label: { Text(info.studentID) }
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                        Toggle("显示敏感信息", isOn: $showsSensitive)
                        AppNavigationLink { AcademicAdministrativeContactsView() } label: { Label("行政班同学通讯录", systemImage: "person.2") }
                        if let photoError { Text(photoError).font(.caption).foregroundStyle(.secondary) }
                        Button("刷新学籍照片", systemImage: "arrow.clockwise") { Task { await loadPhoto() } }
                    }

                    fieldSection("学籍信息", keys: ["院系", "院系名称", "学院", "专业", "专业名称", "专业方向", "行政班", "班级", "校区", "培养方案", "学籍状态", "学历层次", "学制", "入学日期", "预计毕业日期"])
                    fieldSection("基本信息", keys: ["性别", "政治面貌", "生源地"])
                    fieldSection("联系方式", keys: ["邮箱", "电话", "手机", "地址", "邮编"])

                    Section("账号安全") {
                        AcademicPasswordChangeLink()
                    }

                    let remaining = remainingFields(info)
                    if !remaining.isEmpty {
                        Section("其他信息") {
                            ForEach(remaining, id: \.key) { item in
                                LabeledContent(item.key, value: displayedValue(item.value, key: item.key)).textSelection(.enabled)
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            } else {
                ContentUnavailableView {
                    Label("尚未同步学籍信息", systemImage: "person.crop.circle.badge.questionmark")
                } description: {
                    Text(studentStore.error ?? "正在同步个人信息；若登录已过期，请重新登录。")
                } actions: {
                    Button("重新读取") { Task { await studentStore.refresh(force: true) } }.disabled(studentStore.loading)
                    Button("安全登录") { showingLogin = true }
                }
            }
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("个人信息")
        .refreshable { await studentStore.refresh(force: true) }
        .overlay { if studentStore.loading { ProgressView() } }
        .task { await studentStore.refresh(); if studentStore.info != nil && photo == nil { await loadPhoto() } }
        .sheet(isPresented: $showingLogin, onDismiss: { Task { await studentStore.refresh(force: true) } }) { AppNavigationStack { LoginPortalView() } }
    }

    @ViewBuilder
    private func fieldSection(_ title: String, keys: [String]) -> some View {
        if let info = studentStore.info {
            let rows = keys.compactMap { key -> (key: String, value: String)? in
                guard let value = info.fields[key], !value.isEmpty else { return nil }
                return (key, value)
            }
            if !rows.isEmpty {
                Section(title) {
                    ForEach(rows, id: \.key) { item in
                        LabeledContent(item.key, value: displayedValue(item.value, key: item.key)).textSelection(.enabled)
                    }
                }
            }
        }
    }

    private func displayedValue(_ value: String, key: String) -> String {
        let sensitive = ["身份证", "证件", "电话", "手机", "邮箱", "邮件", "地址", "密码", "生日", "出生"]
        return !showsSensitive && sensitive.contains(where: { key.contains($0) }) ? "••••••" : value
    }

    @MainActor private func loadPhoto() async {
        photoError = nil
        do {
            let mode = AcademicConnectionMode(rawValue: UserDefaults.standard.string(forKey: "academicConnectionMode") ?? "") ?? .direct
            let data = try await AcademicClient(mode: mode, cookies: CampusSessionStore.shared.allCookies).studentPhoto()
            guard let image = UIImage(data: data) else { throw AcademicClientError.invalidData("校方未返回可识别的学籍照片") }
            photo = image
        } catch { AcademicServiceDiagnostics.record(context: "学籍照片读取", error: error); photoError = error.localizedDescription }
    }

    private func remainingFields(_ info: AcademicStudentInfo) -> [(key: String, value: String)] {
        let known = Set(["院系", "院系名称", "学院", "专业", "专业名称", "专业方向", "行政班", "班级", "校区", "培养方案", "学籍状态", "学历层次", "学制", "入学日期", "预计毕业日期", "性别", "政治面貌", "生源地", "邮箱", "电话", "手机", "地址", "邮编"])
        return info.fields
            .filter { !known.contains($0.key) && !$0.value.isEmpty }
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
    }
}

/// The same authenticated account page used by upstream's password settings.
struct AcademicPasswordChangeLink: View {
    @AppStorage("academicConnectionMode") private var connectionMode = AcademicConnectionMode.direct.rawValue

    private var selectedMode: AcademicConnectionMode {
        AcademicConnectionMode(rawValue: connectionMode) ?? .direct
    }

    var body: some View {
        AppNavigationLink {
            PortalWebView(url: AcademicPortal.url("my/account", mode: selectedMode))
                .navigationTitle("修改教务密码")
                .navigationBarTitleDisplayMode(.inline)
                .onDisappear {
                    let mode = selectedMode
                    Task {
                        _ = await AcademicClient(mode: mode, cookies: CampusSessionStore.shared.allCookies)
                            .refreshAcademicPasswordIfAvailable()
                    }
                }
        } label: {
            Label("修改教务系统密码", systemImage: "lock.rotation")
        }
    }
}
