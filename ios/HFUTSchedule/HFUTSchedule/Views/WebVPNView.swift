import SwiftUI
import UIKit

@MainActor
struct NativeWebVPNView: View {
    @AppStorage("academicConnectionMode") private var connectionMode = AcademicConnectionMode.direct.rawValue
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Namespace private var resultTransition
    @StateObject private var model: WebVPNConversionModel
    @ObservedObject private var browsingSession = WebVPNBrowsingSession.shared
    @State private var hasSession = false
    @State private var showingLogin = false
    @State private var showingLoginPrompt = false
    @State private var copied = false
    @State private var openedResult: OpenedResult?

    private struct OpenedResult: Identifiable, Hashable {
        let url: URL
        var id: String { url.absoluteString }
    }

    init() {
        _model = StateObject(wrappedValue: WebVPNConversionModel())
    }

    init(model: WebVPNConversionModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        List {
            Section {
                Picker("网址转换方式", selection: $model.direction) {
                    ForEach(WebVPNConversionModel.Direction.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            explanation
            inputSection
            if let result = model.result { resultSection(result) }
            if model.direction == .toWebVPN { globalConversionSection }
            loginSection
        }
        .navigationTitle("WebVPN")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refreshStatus)
        .onChange(of: scenePhase) { _, phase in if phase == .active { refreshStatus() } }
        .onChange(of: model.input) { _, _ in copied = false }
        .onChange(of: model.direction) { _, _ in copied = false }
        .sheet(isPresented: $showingLogin, onDismiss: refreshStatus) {
            AppNavigationStack { LoginPortalView() }
        }
        .navigationDestination(item: $openedResult) { link in
            if #available(iOS 18.0, *), !reduceMotion {
                PortalWebView(url: link.url)
                    .navigationTransition(.zoom(sourceID: "webvpn-result-open", in: resultTransition))
            } else {
                PortalWebView(url: link.url)
            }
        }
        .alert("请先登录 WebVPN", isPresented: $showingLoginPrompt) {
            Button("使用校外访问登录") { beginLogin() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("网址转换无需登录。打开转换后的链接或启用全局转换前，请先使用校外访问模式完成统一身份认证。")
        }
    }

    private var explanation: some View {
        Section {
            Text(model.direction == .toWebVPN
                ? "输入仅校园网可访问的网址，转换后可在登录 WebVPN 的前提下从校外访问。"
                : "输入合工大 WebVPN 链接，还原为原始网址。还原操作无需登录。")
                .font(.footnote).foregroundStyle(.secondary)
            if model.direction == .toWebVPN {
                example("座位预约", url: "http://210.45.242.57/")
                example("图书馆", url: "https://lib.hfut.edu.cn/")
            } else {
                example("教务系统", url: AcademicPortal.webVPNAcademicRoot.absoluteString)
            }
        } header: { Text("点击示例填入") }
    }

    private func example(_ title: String, url: String) -> some View {
        Button { model.input = url } label: {
            VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: "link")
                Text(url).font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
        }.buttonStyle(.plain)
    }

    private var inputSection: some View {
        Section {
            TextField(model.direction == .toWebVPN ? "http:// 或 https:// 开头的网址" : "https://webvpn.hfut.edu.cn/…",
                      text: Binding(get: { model.input }, set: { model.input = $0 }), axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .lineLimit(2...6)
                .accessibilityLabel("待转换的网址")
            HStack {
                Button(model.direction.title, systemImage: "arrow.triangle.2.circlepath") {
                    model.convert(); copied = false
                }
                .disabled(!model.canConvert)
                Spacer()
                Button("清空输入", systemImage: "xmark.circle") { model.input = "" }
                    .labelStyle(.iconOnly).disabled(model.input.isEmpty)
            }
        } header: { Text("输入链接") } footer: {
            if !model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.canConvert {
                Text(model.direction == .toWebVPN
                    ? "请输入有效的 HTTP 或 HTTPS 网址。"
                    : "请输入有效的合工大 WebVPN 加密链接。门户首页或登录页不是可还原的链接。")
            }
        }
    }

    private func resultSection(_ result: URL) -> some View {
        Section {
            Text(result.absoluteString).font(.footnote.monospaced()).textSelection(.enabled)
                .accessibilityLabel("转换结果：\(result.absoluteString)")
            resultActionsLayout { resultActions(result) }
            .buttonStyle(.borderless)
            .font(.subheadline)
        } header: { Text("转换结果") } footer: {
            if model.direction == .toOriginal && browsingSession.isEnabled {
                Text("全局 WebVPN 已开启，打开原始链接时仍会走 WebVPN；复制的内容始终为原始链接。")
            }
        }
    }

    private var resultActionsLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 16))
    }

    @ViewBuilder
    private func resultActions(_ result: URL) -> some View {
        Button(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc") {
            UIPasteboard.general.string = result.absoluteString
            copied = true
        }
        if #available(iOS 18.0, *), !reduceMotion {
            Button("打开", systemImage: "arrow.up.right.square", action: openResult)
                .matchedTransitionSource(id: "webvpn-result-open", in: resultTransition)
        } else {
            Button("打开", systemImage: "arrow.up.right.square", action: openResult)
        }
        Button("清除", systemImage: "trash", role: .destructive) { model.clearResult(); copied = false }
    }

    private func openResult() {
        refreshStatus()
        guard model.canOpenResult(hasSession: hasSession), let result = model.result else {
            if model.result != nil { showingLoginPrompt = true }
            return
        }
        openedResult = OpenedResult(url: result)
    }

    private var globalConversionSection: some View {
        Section {
            Toggle("全局 WebVPN", isOn: Binding(get: { browsingSession.isEnabled }, set: { value in
                hasSession = WebVPNBrowsingSession.hasSavedSession()
                if !browsingSession.setEnabled(value, hasSession: hasSession) { showingLoginPrompt = true }
            }))
            .disabled(!hasSession)
        } footer: {
            Text("启用后，App 内新打开的普通网页会自动转换；仅在保存 WebVPN 登录会话时可用，重新启动 App 后关闭。")
        }
    }

    private var loginSection: some View {
        Section("校外访问") {
            Label(hasSession ? "已保存 WebVPN 会话" : "尚未登录 WebVPN", systemImage: hasSession ? "checkmark.shield.fill" : "lock.shield")
                .foregroundStyle(hasSession ? .green : .secondary)
            Picker("教务连接方式", selection: $connectionMode) {
                ForEach(AcademicConnectionMode.allCases) { Text($0.title).tag($0.rawValue) }
            }
            Button("使用统一身份认证登录", systemImage: "person.badge.key") { beginLogin() }
            SourceAnchoredNavigationLink(sourceID: "webvpn-login") {
                PortalWebView(url: URL(string: "https://webvpn.hfut.edu.cn/login?cas_login=true")!)
            } label: { Label("打开 WebVPN 门户", systemImage: "rectangle.portrait.and.arrow.right") }
        }
    }

    private func beginLogin() {
        connectionMode = AcademicConnectionMode.webVPN.rawValue
        showingLogin = true
    }

    private func refreshStatus() {
        hasSession = WebVPNBrowsingSession.hasSavedSession()
        if !hasSession { _ = browsingSession.setEnabled(false, hasSession: false) }
    }
}
