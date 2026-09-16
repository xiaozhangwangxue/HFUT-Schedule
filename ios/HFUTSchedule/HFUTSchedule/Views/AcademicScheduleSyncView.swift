import SwiftUI
import WebKit

struct AcademicScheduleSyncView: View {
    @EnvironmentObject private var scheduleStore: ScheduleStore
    @EnvironmentObject private var notificationManager: CourseNotificationManager
    @Environment(\.dismiss) private var dismiss
    @State private var syncTrigger = 0
    @State private var pageReady = false
    @State private var status = "请在校方页面完成统一身份认证"
    @State private var isSyncing = false
    @State private var resultMessage: String?
    @AppStorage("academicConnectionMode") private var connectionMode = AcademicConnectionMode.direct.rawValue

    private var selectedMode: AcademicConnectionMode {
        AcademicConnectionMode(rawValue: connectionMode) ?? .direct
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                AcademicWebView(
                    syncTrigger: syncTrigger,
                    semesterID: AcademicPortal.currentSemesterID,
                    connectionMode: selectedMode,
                    onPageReady: {
                        guard !pageReady else { return }
                        pageReady = true
                        status = "登录完成，正在自动同步课表…"
                        isSyncing = true
                        syncTrigger += 1
                    },
                    onResult: handleSyncResult
                )
                .id(selectedMode)
                .ignoresSafeArea(edges: .bottom)

                VStack(spacing: 10) {
                    Picker("访问方式", selection: $connectionMode) {
                        ForEach(AcademicConnectionMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(status)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button(isSyncing ? "正在同步…" : "同步课表", systemImage: "arrow.triangle.2.circlepath") {
                        isSyncing = true
                        status = "正在读取本学期教务课表…"
                        syncTrigger += 1
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!pageReady || isSyncing)
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .adaptiveGlass(cornerRadius: 24, interactive: true)
                .padding(12)
            }
            .navigationTitle("教务课表同步")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .alert("课表同步", isPresented: Binding(
                get: { resultMessage != nil },
                set: { if !$0 { resultMessage = nil } }
            )) {
                Button("完成") { dismiss() }
                Button("继续查看", role: .cancel) { resultMessage = nil }
            } message: {
                Text(resultMessage ?? "")
            }
        }
    }

    private func handleSyncResult(_ result: Result<AcademicSyncPayload, Error>) {
        isSyncing = false
        switch result {
        case .success(let payload):
            let courses = payload.courses()
            scheduleStore.replaceAcademicCourses(with: courses)
            Task { try? await notificationManager.reschedule(for: scheduleStore.courses) }
            status = "同步完成"
            resultMessage = "已同步 \(courses.count) 个课程时段，保留了手动添加的课程。"
        case .failure(let error):
            status = "同步失败，请确认已登录教务系统"
            resultMessage = error.localizedDescription
        }
    }

}

private struct AcademicWebView: UIViewRepresentable {
    let syncTrigger: Int
    let semesterID: Int
    let connectionMode: AcademicConnectionMode
    let onPageReady: () -> Void
    let onResult: (Result<AcademicSyncPayload, Error>) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 HFUTSchedule-iOS"

        CampusSessionStore.shared.hydrateWebKit(configuration.websiteDataStore.httpCookieStore) {
            webView.load(URLRequest(url: AcademicPortal.loginURL(for: connectionMode)))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        guard syncTrigger > context.coordinator.lastSyncTrigger else { return }
        context.coordinator.lastSyncTrigger = syncTrigger
        CampusSessionStore.shared.captureWebKit(webView.configuration.websiteDataStore.httpCookieStore) { cookies in
            Task {
                do {
                    let payload = try await AcademicClient(mode: connectionMode, cookies: cookies)
                        .fetchSchedule(semesterID: semesterID)
                    await MainActor.run { onResult(.success(payload)) }
                } catch {
                    await MainActor.run { onResult(.failure(error)) }
                }
            }
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: AcademicWebView
        var lastSyncTrigger = 0
        private var enteredAcademicAfterVPNLogin = false

        init(parent: AcademicWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            CampusSessionStore.shared.captureWebKit(webView.configuration.websiteDataStore.httpCookieStore)
            if parent.connectionMode == .webVPN,
               !enteredAcademicAfterVPNLogin,
               AcademicPortal.shouldEnterAcademicAfterWebVPNLogin(webView.url) {
                enteredAcademicAfterVPNLogin = true
                webView.load(URLRequest(url: AcademicPortal.webVPNAcademicRoot.appendingPathComponent("neusoft-sso/login")))
                return
            }
            guard AcademicPortal.isAcademicPage(webView.url, mode: parent.connectionMode) else { return }
            DispatchQueue.main.async { self.parent.onPageReady() }
        }
    }
}
