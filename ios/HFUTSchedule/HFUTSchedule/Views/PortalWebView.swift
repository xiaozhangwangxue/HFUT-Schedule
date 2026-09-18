import SwiftUI
import WebKit

struct PortalWebView: View {
    let url: URL
    var academicMode: AcademicConnectionMode?
    var onAcademicAuthenticated: (([HTTPCookie]) -> Void)?
    var autoOpenCampusMailbox = false
    @State private var isLoading = true
    @State private var title = ""

    init(
        url: URL,
        academicMode: AcademicConnectionMode? = nil,
        onAcademicAuthenticated: (([HTTPCookie]) -> Void)? = nil,
        autoOpenCampusMailbox: Bool = false
    ) {
        self.url = url
        self.academicMode = academicMode
        self.onAcademicAuthenticated = onAcademicAuthenticated
        self.autoOpenCampusMailbox = autoOpenCampusMailbox
    }

    var body: some View {
        ZStack(alignment: .top) {
            WebViewRepresentable(
                url: url,
                academicMode: academicMode,
                onAcademicAuthenticated: onAcademicAuthenticated,
                autoOpenCampusMailbox: autoOpenCampusMailbox,
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
        .navigationTitle(title.isEmpty ? "校园门户" : title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct WebViewRepresentable: UIViewRepresentable {
    let url: URL
    let academicMode: AcademicConnectionMode?
    let onAcademicAuthenticated: (([HTTPCookie]) -> Void)?
    let autoOpenCampusMailbox: Bool
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

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 HFUTSchedule-iOS"
        context.coordinator.didRequestInitialLoad = true
        CampusSessionStore.shared.hydrateWebKit(configuration.websiteDataStore.httpCookieStore) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        guard !context.coordinator.didRequestInitialLoad else { return }
        context.coordinator.didRequestInitialLoad = true
        webView.load(URLRequest(url: url))
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
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            parent.isLoading = false
            parent.pageTitle = webView.title ?? "校园门户"
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
