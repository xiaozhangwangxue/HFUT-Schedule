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

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                AcademicWebView(
                    syncTrigger: syncTrigger,
                    semesterID: Self.currentSemesterID,
                    onPageReady: {
                        pageReady = true
                        status = "登录完成后点击“同步课表”"
                    },
                    onResult: handleSyncResult
                )
                .ignoresSafeArea(edges: .bottom)

                VStack(spacing: 10) {
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

    private static var currentSemesterID: Int {
        let components = Calendar.current.dateComponents([.year, .month], from: Date())
        let year = components.year ?? 2026
        let month = components.month ?? 9
        let startYear = month <= 7 ? year - 1 : year
        let firstSemester = ((startYear - 2018) * 4 + 3) * 10 + 4
        return month <= 7 && month >= 2 ? firstSemester + 20 : firstSemester
    }
}

private struct AcademicWebView: UIViewRepresentable {
    let syncTrigger: Int
    let semesterID: Int
    let onPageReady: () -> Void
    let onResult: (Result<AcademicSyncPayload, Error>) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(context.coordinator, name: "hfutScheduleSync")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 HFUTSchedule-iOS"

        var loginComponents = URLComponents(string: "https://cas.hfut.edu.cn/cas/login")!
        loginComponents.queryItems = [
            URLQueryItem(
                name: "service",
                value: "http://jxglstu.hfut.edu.cn/eams5-student/neusoft-sso/login"
            )
        ]
        let loginURL = loginComponents.url!
        webView.load(URLRequest(url: loginURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        guard syncTrigger > context.coordinator.lastSyncTrigger else { return }
        context.coordinator.lastSyncTrigger = syncTrigger
        webView.evaluateJavaScript(syncScript) { _, error in
            if let error { onResult(.failure(error)) }
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "hfutScheduleSync")
    }

    private var syncScript: String {
        """
        (async function() {
          const send = (value) => window.webkit.messageHandlers.hfutScheduleSync.postMessage(value);
          try {
            const tableResponse = await fetch('/eams5-student/for-std/course-table', { credentials: 'include' });
            const tableHTML = await tableResponse.text();
            const studentMatch = tableResponse.url.match(/course-table\\/info\\/(\\d+)/);
            const bizMatch = tableHTML.match(/bizTypeId\\s*:\\s*(\\d+)/);
            if (!studentMatch || !bizMatch) throw new Error('未获取到教务身份，请先完成登录');
            const studentID = Number(studentMatch[1]);
            const bizTypeID = Number(bizMatch[1]);
            const termURL = `/eams5-student/for-std/course-table/get-data?bizTypeId=${bizTypeID}&semesterId=\(semesterID)&dataId=${studentID}`;
            const termResponse = await fetch(termURL, { credentials: 'include' });
            if (!termResponse.ok) throw new Error(`课表索引请求失败 ${termResponse.status}`);
            const term = await termResponse.json();
            const datumResponse = await fetch('/eams5-student/ws/schedule-table/datum', {
              method: 'POST',
              credentials: 'include',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ lessonIds: term.lessonIds, studentId: studentID, weekIndex: '' })
            });
            if (!datumResponse.ok) throw new Error(`课表数据请求失败 ${datumResponse.status}`);
            const datum = await datumResponse.json();
            send({ ok: true, payload: { term, datum } });
          } catch (error) {
            send({ ok: false, message: error && error.message ? error.message : String(error) });
          }
        })();
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: AcademicWebView
        var lastSyncTrigger = 0

        init(parent: AcademicWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            guard let host = webView.url?.host?.lowercased(),
                  host == "jxglstu.hfut.edu.cn"
            else { return }
            DispatchQueue.main.async { self.parent.onPageReady() }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let object = message.body as? [String: Any], let ok = object["ok"] as? Bool else {
                parent.onResult(.failure(AcademicSyncError.invalidResponse))
                return
            }
            if !ok {
                let text = object["message"] as? String ?? "教务系统返回未知错误"
                parent.onResult(.failure(AcademicSyncError.remote(text)))
                return
            }
            do {
                guard let payload = object["payload"] else { throw AcademicSyncError.invalidResponse }
                let data = try JSONSerialization.data(withJSONObject: payload)
                let decoded = try JSONDecoder().decode(AcademicSyncPayload.self, from: data)
                parent.onResult(.success(decoded))
            } catch {
                parent.onResult(.failure(error))
            }
        }
    }
}

private enum AcademicSyncError: LocalizedError {
    case invalidResponse
    case remote(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "无法解析教务系统返回的数据。"
        case .remote(let message): message
        }
    }
}
