import SwiftUI
import WebKit

@MainActor
struct PortalWebView: View {
    let url: URL
    var academicMode: AcademicConnectionMode?
    var onAcademicAuthenticated: (([HTTPCookie]) -> Void)?
    var autoOpenCampusMailbox = false
    var cookieHeader: String?
    @State private var isLoading = true
    @State private var title = ""
    @StateObject private var webViewReference = PortalBrowserController()
    @Environment(\.openURL) private var openURL
    @State private var showsFind = false
    @State private var findText = ""
    @State private var showsCookieEditor = false
    @State private var temporaryCookie = ""
    @State private var favoriteURL: URL?
    @State private var favoriteTitle = ""
    @State private var toolMessage: String?
    @State private var isExtractingSummary = false
    @State private var summaryPage: DeepSeekWebPageContext?
    @State private var summaryError: String?

    init(
        url: URL,
        academicMode: AcademicConnectionMode? = nil,
        onAcademicAuthenticated: (([HTTPCookie]) -> Void)? = nil,
        autoOpenCampusMailbox: Bool = false,
        cookieHeader: String? = nil
    ) {
        self.url = url
        self.academicMode = academicMode
        self.onAcademicAuthenticated = onAcademicAuthenticated
        self.autoOpenCampusMailbox = autoOpenCampusMailbox
        self.cookieHeader = cookieHeader
    }

    var body: some View {
        ZStack(alignment: .top) {
            WebViewRepresentable(
                url: url,
                academicMode: academicMode,
                onAcademicAuthenticated: onAcademicAuthenticated,
                autoOpenCampusMailbox: autoOpenCampusMailbox,
                reference: webViewReference,
                cookieHeader: cookieHeader,
                isLoading: $isLoading,
                pageTitle: $title
            )
                .ignoresSafeArea(edges: .bottom)

            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .adaptiveGlass(cornerRadius: 18)
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: isLoading)
        .overlay(alignment: .bottom) {
            if let error = webViewReference.errorMessage {
                VStack(spacing: 8) {
                    Text(error).font(.footnote)
                    Button("关闭提示") { webViewReference.errorMessage = nil }
                }.padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)).padding()
            }
        }
        .navigationTitle(title.isEmpty ? "校园门户" : title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: prepareSummary) {
                    if isExtractingSummary { ProgressView() }
                    else { Label("AI 摘要", systemImage: "sparkles") }
                }
                .disabled(isLoading || isExtractingSummary)
                .accessibilityLabel("使用 AI 概括当前网页")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu("网页工具", systemImage: "ellipsis.circle") {
                    Button("后退", systemImage: "chevron.left") { webViewReference.goBack() }.disabled(!webViewReference.canGoBack)
                    Button("前进", systemImage: "chevron.right") { webViewReference.goForward() }.disabled(!webViewReference.canGoForward)
                    Button("刷新", systemImage: "arrow.clockwise") { webViewReference.reload() }
                    Button("页面内搜索", systemImage: "text.magnifyingglass") { showsFind = true }
                    Menu("当前链接", systemImage: "link") { linkTools(webViewReference.currentURL ?? url) }
                    Menu("初始链接", systemImage: "link.badge.plus") { linkTools(url) }
                    Button("设置临时 Cookie", systemImage: "key") { showsCookieEditor = true }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if showsFind {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        TextField("在当前网页查找", text: $findText)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .onSubmit { webViewReference.find(findText) }
                        Button("上一处", systemImage: "chevron.up") { webViewReference.find(findText, backwards: true) }.labelStyle(.iconOnly)
                        Button("下一处", systemImage: "chevron.down") { webViewReference.find(findText) }.labelStyle(.iconOnly)
                        Button("关闭查找", systemImage: "xmark") { showsFind = false; webViewReference.clearFind() }.labelStyle(.iconOnly)
                    }
                    if let message = webViewReference.findMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
                }.padding().background(.bar)
            }
        }
        .sheet(isPresented: $showsCookieEditor) {
            AppNavigationStack {
                Form {
                    TextField("name=value; name2=value2", text: $temporaryCookie, axis: .vertical)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("只应用于当前网页所在主机，并重新载入该网页。").font(.caption).foregroundStyle(.secondary)
                }
                .navigationTitle("临时 Cookie")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { showsCookieEditor = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("应用并刷新") {
                            Task { @MainActor in
                                do {
                                    try await webViewReference.applyCookieHeader(temporaryCookie, to: webViewReference.currentURL ?? url)
                                    temporaryCookie = ""; showsCookieEditor = false
                                } catch { toolMessage = error.localizedDescription }
                            }
                        }.disabled(temporaryCookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .alert("网页工具", isPresented: Binding(get: { toolMessage != nil }, set: { if !$0 { toolMessage = nil } })) {
                    Button("好") { toolMessage = nil }
                } message: { Text(toolMessage ?? "") }
            }
        }
        .alert("添加收藏", isPresented: Binding(get: { favoriteURL != nil }, set: { if !$0 { favoriteURL = nil } })) {
            TextField("网页名称", text: $favoriteTitle)
            Button("取消", role: .cancel) { favoriteURL = nil }
            Button("保存") {
                if let favoriteURL { try? WebFavoriteStore.save(title: favoriteTitle, url: favoriteURL) }
                favoriteURL = nil
            }
        } message: { Text(favoriteURL?.absoluteString ?? "") }
        .navigationDestination(item: $summaryPage) { page in
            AIAssistantView(page: page)
        }
        .alert("无法读取网页", isPresented: Binding(
            get: { summaryError != nil },
            set: { if !$0 { summaryError = nil } }
        )) {
            Button("好", role: .cancel) { summaryError = nil }
        } message: {
            Text(summaryError ?? "")
        }
    }

    @ViewBuilder
    private func linkTools(_ target: URL) -> some View {
        Button("复制链接", systemImage: "doc.on.doc") { UIPasteboard.general.string = target.absoluteString }
        ShareLink(item: target) { Label("分享链接", systemImage: "square.and.arrow.up") }
        Button("在浏览器中打开", systemImage: "safari") { openURL(target) }
        Button(WebFavoriteStore.contains(target) ? "已收藏 · 修改名称" : "添加收藏", systemImage: "star") {
            favoriteTitle = title.isEmpty ? target.host ?? "网页" : title
            favoriteURL = target
        }
        if WebFavoriteStore.contains(target) {
            Button("取消收藏", systemImage: "star.slash", role: .destructive) { try? WebFavoriteStore.remove(target) }
        }
    }

    @MainActor
    private func prepareSummary() {
        guard let webView = webViewReference.webView else { return }
        isExtractingSummary = true
        webView.evaluateJavaScript("document.body ? document.body.innerText : ''") { result, error in
            isExtractingSummary = false
            guard error == nil, let text = result as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                summaryError = "当前页面没有可读取的正文，请等待网页加载完成后重试。"
                return
            }
            summaryPage = DeepSeekWebPageContext(
                title: webView.title ?? title,
                sourceURL: webView.url ?? url,
                text: text
            )
        }
    }
}

private struct WebViewRepresentable: UIViewRepresentable {
    let url: URL
    let academicMode: AcademicConnectionMode?
    let onAcademicAuthenticated: (([HTTPCookie]) -> Void)?
    let autoOpenCampusMailbox: Bool
    let reference: PortalBrowserController
    let cookieHeader: String?
    @Binding var isLoading: Bool
    @Binding var pageTitle: String

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        if autoOpenCampusMailbox {
            configuration.userContentController.addUserScript(
                WKUserScript(
                    source: Self.openCampusMailboxScript,
                    injectionTime: .atDocumentEnd,
                    forMainFrameOnly: true
                )
            )
        }
        if UserDefaults.standard.bool(forKey: AppSettingsKey.webDarkMode) {
            configuration.userContentController.addUserScript(
                WKUserScript(
                    source: Self.forceDarkModeScript,
                    injectionTime: .atDocumentEnd,
                    forMainFrameOnly: false
                )
            )
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        reference.webView = webView
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 HFUTSchedule-iOS"
        context.coordinator.didRequestInitialLoad = true
        CampusSessionStore.shared.hydrateWebKit(configuration.websiteDataStore.httpCookieStore) {
            Task { @MainActor in
                let target = initialURL()
                if let cookieHeader, !cookieHeader.isEmpty {
                    do { try await reference.applyCookieHeader(cookieHeader, to: target) }
                    catch { reference.errorMessage = error.localizedDescription }
                } else { webView.load(URLRequest(url: target)) }
            }
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        guard !context.coordinator.didRequestInitialLoad else { return }
        context.coordinator.didRequestInitialLoad = true
        webView.load(URLRequest(url: initialURL()))
    }

    @MainActor
    private func initialURL() -> URL {
        WebVPNBrowsingSession.shared.initialURL(
            url,
            isProtectedFlow: academicMode != nil || onAcademicAuthenticated != nil || autoOpenCampusMailbox
        )
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: WebViewRepresentable
        private var enteredAcademicAfterVPNLogin = false
        private var reportedAuthentication = false
        var didRequestInitialLoad = false

        init(parent: WebViewRepresentable) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation?) {
            parent.isLoading = true
            parent.reference.synchronize()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            parent.isLoading = false
            parent.pageTitle = webView.title ?? "校园门户"
            parent.reference.synchronize()
            CampusSessionStore.shared.captureWebKit(webView.configuration.websiteDataStore.httpCookieStore)
            if parent.academicMode == .webVPN,
               !enteredAcademicAfterVPNLogin,
               AcademicPortal.shouldEnterAcademicAfterWebVPNLogin(webView.url) {
                enteredAcademicAfterVPNLogin = true
                webView.load(URLRequest(url: AcademicPortal.webVPNAcademicRoot.appendingPathComponent("neusoft-sso/login")))
                return
            }
            guard let mode = parent.academicMode,
                  !reportedAuthentication,
                  AcademicPortal.isAcademicPage(webView.url, mode: mode) else { return }
            reportedAuthentication = true
            CampusSessionStore.shared.captureWebKit(webView.configuration.websiteDataStore.httpCookieStore) { [parent] cookies in
                parent.onAcademicAuthenticated?(cookies)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: Error) {
            parent.isLoading = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: Error) {
            parent.isLoading = false
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let target = navigationAction.request.url,
                  let scheme = target.scheme?.lowercased(),
                  !["http", "https", "about"].contains(scheme) else {
                decisionHandler(.allow)
                return
            }
            UIApplication.shared.open(target)
            decisionHandler(.cancel)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil, let target = navigationAction.request.url {
                webView.load(URLRequest(url: target))
            }
            return nil
        }
    }

    /// The portal owns the current mailbox route. Follow the same visible
    /// “未读 N 封” control the user taps on the official page instead of
    /// hard-coding a mailbox host that may change.
    /// 强制网页深色模式（对应上游「外观-强制网页深色模式」）。
    private static let forceDarkModeScript = #"""
    (() => {
      if (window.__hfutForceDark) return;
      window.__hfutForceDark = true;
      const style = document.createElement('style');
      style.textContent = `
        html { background: #101114 !important; }
        body, main, section, article, div, table, td, th, ul, ol, li, p, span, label, form {
          background-color: transparent !important;
          color: #E6E3DF !important;
          border-color: rgba(255,255,255,0.14) !important;
        }
        html, body { background-color: #101114 !important; }
        a, a:visited { color: #7FB3FF !important; }
        input, textarea, select { background: #1B1D21 !important; color: #E6E3DF !important; }
        img, video, canvas { filter: brightness(0.92); }
      `;
      document.documentElement.appendChild(style);
    })();
    """#

    private static let openCampusMailboxScript = #"""
    (() => {
      if (window.__hfutMailboxLinkWatcher || location.hostname !== 'one.hfut.edu.cn') return;
      window.__hfutMailboxLinkWatcher = true;
      let state = { attempts: 0 };
      const timer = setInterval(() => {
        state.attempts += 1;
        const candidate = Array.from(document.querySelectorAll('a, button, [role="button"], span, div'))
          .find((element) => {
            const text = (element.innerText || element.textContent || '').replace(/\s+/g, '');
            return /^未读\d+封/.test(text) && text.length <= 12;
          });
        if (candidate) {
          clearInterval(timer);
          candidate.click();
        } else if (state.attempts >= 40) {
          clearInterval(timer);
        }
      }, 300);
    })();
    """#
}
