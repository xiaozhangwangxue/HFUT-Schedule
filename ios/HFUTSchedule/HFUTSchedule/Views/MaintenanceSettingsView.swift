import SwiftUI
import UniformTypeIdentifiers

struct MaintenanceSettingsView: View {
    @State private var releases: [AppRelease] = []
    @State private var loading = false
    @State private var status = "尚未检查在线版本"
    @State private var diagnostics = ""
    var body: some View {
        List {
            Section("版本") {
                LabeledContent("当前版本", value: AppInfo.version)
                Text(status).font(.footnote).foregroundStyle(.secondary)
                Button { Task { await check() } } label: {
                    HStack { Label("检查更新", systemImage: "arrow.clockwise"); if loading { ProgressView() } }
                }.disabled(loading)
                if let latest = releases.first {
                    Link("打开 \(latest.tagName) 下载页", destination: latest.htmlURL)
                }
            }
            Section("更新记录") {
                if releases.isEmpty { Text("检查更新后显示 iOS 正式版的完整更新说明。").font(.footnote).foregroundStyle(.secondary) }
                ForEach(releases) { release in
                    AppNavigationLink {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(release.name ?? release.tagName).font(.title2.bold())
                                if let date = release.publishedAt { Text(date).font(.caption).foregroundStyle(.secondary) }
                                Text(release.body ?? "此版本未提供更新说明。").textSelection(.enabled)
                                Link("在 GitHub 查看", destination: release.htmlURL)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding()
                        }.navigationTitle(release.tagName)
                    } label: { VStack(alignment: .leading) { Text(release.name ?? release.tagName); Text(release.publishedAt ?? "").font(.caption).foregroundStyle(.secondary) } }
                }
            }
            Section("维护") {
                AppNavigationLink("验证码识别模型") { CaptchaModelSettingsView() }
                AppNavigationLink("运行诊断") {
                    ScrollView { Text(diagnostics).font(.footnote.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding() }
                        .navigationTitle("运行诊断")
                        .toolbar { ShareLink(item: diagnostics) { Label("导出诊断", systemImage: "square.and.arrow.up") } }
                }
                AppNavigationLink("开发者选项") { DeveloperInfoView() }
            }
            Section("开源") {
                Link("iOS 源代码", destination: URL(string: "https://github.com/xiaozhangwangxue/HFUT-Schedule")!)
                Link("Android 原项目", destination: URL(string: "https://github.com/Chiu-xaH/HFUT-Schedule")!)
                Text("基于 Chiu-xaH/HFUT-Schedule 移植，遵循 Apache License 2.0。").font(.footnote)
            }
        }.navigationTitle("维护与关于")
            .task { diagnostics = AppDiagnostics.report() }
    }
    @MainActor private func check() async {
        loading = true; defer { loading = false }
        do {
            releases = try await AppReleaseClient().releases()
            if let latest = releases.first {
                let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
                status = AppReleaseClient.compare(latest.version, current) == .orderedDescending
                    ? "发现新版本 \(latest.version)" : "当前已是最新 iOS 正式版（\(latest.version)）"
            }
        } catch { status = "检查未完成：\(error.localizedDescription)" }
    }
}

struct CaptchaModelSettingsView: View {
    @AppStorage("enableOcrCaptcha") private var enabled = true
    @State private var importing = false
    @State private var task: Task<Void, Never>?
    @State private var status = CaptchaModelStore.statusText
    @State private var message: String?
    @State private var deleting = false
    var body: some View {
        Form {
            Section { Toggle("自动填写图片验证码", isOn: $enabled) } footer: { Text("仅在本机识别，不自动提交登录。") }
            Section("Tesseract 模型") {
                LabeledContent("当前模型", value: status)
                Text("App 已包含原项目模型。可从原项目重新下载，或导入兼容的 .traineddata 文件；安装前会验证模型能否加载。").font(.footnote).foregroundStyle(.secondary)
                if task != nil {
                    HStack { ProgressView(); Text("正在下载或验证模型…") }
                    Button("取消") { task?.cancel() }
                } else {
                    Button("从原项目下载模型") { run { try await CaptchaModelStore.download() } }
                    Button("导入本地模型") { importing = true }
                    if CaptchaModelStore.hasCustomModel { Button("删除用户模型", role: .destructive) { deleting = true } }
                }
            }
        }.navigationTitle("验证码识别")
            .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "traineddata") ?? .data]) { result in
                do {
                    let url = try result.get()
                    run {
                        let granted = url.startAccessingSecurityScopedResource()
                        defer { if granted { url.stopAccessingSecurityScopedResource() } }
                        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                        guard size > 0, size <= CaptchaModelStore.maximumBytes else { throw CaptchaModelStore.ModelError.invalidSize }
                        let data = try Data(contentsOf: url, options: .mappedIfSafe)
                        try await CaptchaModelStore.installAsync(data)
                    }
                } catch { message = error.localizedDescription }
            }
            .confirmationDialog("删除后将恢复内置原版模型。", isPresented: $deleting, titleVisibility: .visible) {
                Button("删除用户模型", role: .destructive) {
                    do { try CaptchaModelStore.removeCustom(); status = CaptchaModelStore.statusText } catch { message = error.localizedDescription }
                }
            }
            .alert("识别模型", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("好") { message = nil }
            } message: { Text(message ?? "") }
            .onDisappear { task?.cancel() }
    }
    private func run(_ operation: @escaping () async throws -> Void) {
        task = Task {
            do { try await operation(); if !Task.isCancelled { status = CaptchaModelStore.statusText; message = "模型安装成功" } }
            catch { if !Task.isCancelled { message = error.localizedDescription } }
            task = nil
        }
    }
}
