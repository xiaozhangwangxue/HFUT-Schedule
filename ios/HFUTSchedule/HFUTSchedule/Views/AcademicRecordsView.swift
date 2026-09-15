import SwiftUI
import WebKit

enum AcademicRecordKind: String {
    case grades
    case exams

    var title: String { self == .grades ? "成绩" : "考试安排" }
    var systemImage: String { self == .grades ? "chart.bar.fill" : "doc.text.fill" }
}

struct AcademicRecordsView: View {
    let kind: AcademicRecordKind
    @EnvironmentObject private var store: AcademicRecordsStore
    @State private var showingSync = false

    var body: some View {
        Group {
            if kind == .grades {
                gradesContent
            } else {
                examsContent
            }
        }
        .background(AppTheme.background.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("同步", systemImage: "arrow.triangle.2.circlepath") {
                    showingSync = true
                }
            }
        }
        .sheet(isPresented: $showingSync) {
            AcademicRecordsSyncView(kind: kind)
                .environmentObject(store)
        }
    }

    @ViewBuilder
    private var gradesContent: some View {
        if store.gradeTerms.isEmpty {
            emptyContent(description: "登录教务系统后同步历学期成绩，数据会保存在本机。")
        } else {
            List {
                if let average = scoreAverage {
                    Section {
                        HStack {
                            Label("已出分课程", systemImage: "checkmark.seal.fill")
                            Spacer()
                            Text("\(scoredGrades.count) 门")
                        }
                        HStack {
                            Label("平均分", systemImage: "chart.line.uptrend.xyaxis")
                            Spacer()
                            Text(average.formatted(.number.precision(.fractionLength(2))))
                                .font(.headline.monospacedDigit())
                        }
                    }
                }
                ForEach(store.gradeTerms) { term in
                    Section(term.term) {
                        ForEach(term.grades) { grade in
                            GradeRow(grade: grade)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private var examsContent: some View {
        if store.exams.isEmpty {
            emptyContent(description: "登录教务系统后同步考试时间、地点与课程信息。")
        } else {
            List(store.exams) { exam in
                VStack(alignment: .leading, spacing: 7) {
                    Text(exam.name)
                        .font(.headline)
                    Label(exam.dateTime, systemImage: "clock.fill")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Label(exam.place.isEmpty ? "地点待定" : exam.place, systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
            .scrollContentBackground(.hidden)
        }
    }

    private func emptyContent(description: String) -> some View {
        ContentUnavailableView {
            Label(kind.title, systemImage: kind.systemImage)
        } description: {
            Text(description)
        } actions: {
            Button("登录并同步", systemImage: "person.badge.key.fill") {
                showingSync = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var scoredGrades: [AcademicGrade] {
        store.gradeTerms.flatMap(\.grades).filter { Double($0.score) != nil }
    }

    private var scoreAverage: Double? {
        let values = scoredGrades.compactMap { Double($0.score) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

private struct GradeRow: View {
    let grade: AcademicGrade

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(grade.courseName)
                    .font(.headline)
                Text([grade.lessonCode, "\(grade.credits) 学分", "绩点 \(grade.gpa)"].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !grade.detail.isEmpty {
                    Text(grade.detail)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Text(grade.score)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(scoreColor)
        }
        .padding(.vertical, 4)
    }

    private var scoreColor: Color {
        guard let value = Double(grade.score) else { return .primary }
        return value < 60 ? .red : .primary
    }
}

private struct AcademicRecordsSyncView: View {
    let kind: AcademicRecordKind
    @EnvironmentObject private var store: AcademicRecordsStore
    @Environment(\.dismiss) private var dismiss
    @State private var pageReady = false
    @State private var syncTrigger = 0
    @State private var isSyncing = false
    @State private var status = "请在校方页面完成统一身份认证"
    @State private var resultMessage: String?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                AcademicRecordsWebView(
                    kind: kind,
                    syncTrigger: syncTrigger,
                    onPageReady: {
                        pageReady = true
                        status = "登录完成，点击同步\(kind.title)"
                    },
                    onResult: handleResult
                )
                .ignoresSafeArea(edges: .bottom)

                VStack(spacing: 10) {
                    Text(status)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                    Button(isSyncing ? "正在同步…" : "同步\(kind.title)", systemImage: "arrow.triangle.2.circlepath") {
                        isSyncing = true
                        status = "正在读取教务\(kind.title)…"
                        syncTrigger += 1
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!pageReady || isSyncing)
                }
                .multilineTextAlignment(.center)
                .padding(14)
                .frame(maxWidth: .infinity)
                .adaptiveGlass(cornerRadius: 24, interactive: true)
                .padding(12)
            }
            .navigationTitle("同步\(kind.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .alert("\(kind.title)同步", isPresented: Binding(
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

    private func handleResult(_ result: Result<AcademicRecordsPayload, Error>) {
        isSyncing = false
        switch result {
        case .success(let payload):
            if kind == .grades {
                store.replaceGrades(with: payload.grades)
                let count = payload.grades.flatMap(\.grades).count
                resultMessage = "已同步 \(payload.grades.count) 个学期、\(count) 门课程的成绩。"
            } else {
                store.replaceExams(with: payload.exams)
                resultMessage = "已同步 \(payload.exams.count) 场考试。"
            }
            status = "同步完成"
        case .failure(let error):
            status = "同步失败，请确认已登录教务系统"
            resultMessage = error.localizedDescription
        }
    }
}

private struct AcademicRecordsWebView: UIViewRepresentable {
    let kind: AcademicRecordKind
    let syncTrigger: Int
    let onPageReady: () -> Void
    let onResult: (Result<AcademicRecordsPayload, Error>) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(context.coordinator, name: "hfutAcademicRecords")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 HFUTSchedule-iOS"

        var components = URLComponents(string: "https://cas.hfut.edu.cn/cas/login")!
        components.queryItems = [URLQueryItem(
            name: "service",
            value: "http://jxglstu.hfut.edu.cn/eams5-student/neusoft-sso/login"
        )]
        webView.load(URLRequest(url: components.url!))
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
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "hfutAcademicRecords")
    }

    private var syncScript: String {
        let payloadScript: String
        switch kind {
        case .grades:
            payloadScript = """
            const response = await fetch(`/eams5-student/for-std/grade/sheet/info/${studentID}`, { credentials: 'include' });
            if (!response.ok) throw new Error(`成绩请求失败 ${response.status}`);
            const doc = new DOMParser().parseFromString(await response.text(), 'text/html');
            const headings = Array.from(doc.querySelectorAll('h3'));
            const tables = Array.from(doc.querySelectorAll('table.student-grade-table'));
            const grades = tables.map((table, index) => ({
              term: headings[index] ? headings[index].textContent.trim() : `学期 ${index + 1}`,
              grades: Array.from(table.querySelectorAll('tr')).map(row => Array.from(row.querySelectorAll('td')).map(cell => cell.textContent.trim()))
                .filter(cells => cells.length >= 7)
                .map(cells => ({ courseName: cells[0], lessonCode: cells[2], credits: cells[3], gpa: cells[4], detail: cells[5], score: cells[6] }))
            })).filter(term => term.grades.length > 0);
            send({ ok: true, payload: { grades, exams: [] } });
            """
        case .exams:
            payloadScript = """
            const response = await fetch(`/eams5-student/for-std/exam-arrange/info/${studentID}`, { credentials: 'include' });
            if (!response.ok) throw new Error(`考试请求失败 ${response.status}`);
            const doc = new DOMParser().parseFromString(await response.text(), 'text/html');
            const pattern = /^\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}~\\d{2}:\\d{2}$/;
            const exams = Array.from(doc.querySelectorAll('tbody tr')).map(row => Array.from(row.querySelectorAll('td')).map(cell => cell.textContent.trim()))
              .filter(cells => cells.length >= 3 && pattern.test(cells[1]))
              .map(cells => ({ name: cells[0], dateTime: cells[1], place: cells[2] }));
            send({ ok: true, payload: { grades: [], exams } });
            """
        }

        return """
        (async function() {
          const send = value => window.webkit.messageHandlers.hfutAcademicRecords.postMessage(value);
          try {
            const tableResponse = await fetch('/eams5-student/for-std/course-table', { credentials: 'include' });
            const studentMatch = tableResponse.url.match(/course-table\\/info\\/(\\d+)/);
            if (!studentMatch) throw new Error('未获取到教务身份，请先完成登录');
            const studentID = Number(studentMatch[1]);
            \(payloadScript)
          } catch (error) {
            send({ ok: false, message: error && error.message ? error.message : String(error) });
          }
        })();
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: AcademicRecordsWebView
        var lastSyncTrigger = 0

        init(parent: AcademicRecordsWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            guard webView.url?.host?.lowercased() == "jxglstu.hfut.edu.cn" else { return }
            DispatchQueue.main.async { self.parent.onPageReady() }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let object = message.body as? [String: Any], let ok = object["ok"] as? Bool else {
                parent.onResult(.failure(AcademicRecordsError.invalidResponse))
                return
            }
            if !ok {
                parent.onResult(.failure(AcademicRecordsError.remote(object["message"] as? String ?? "教务系统返回未知错误")))
                return
            }
            do {
                guard let payload = object["payload"] else { throw AcademicRecordsError.invalidResponse }
                let data = try JSONSerialization.data(withJSONObject: payload)
                parent.onResult(.success(try JSONDecoder().decode(AcademicRecordsPayload.self, from: data)))
            } catch {
                parent.onResult(.failure(error))
            }
        }
    }
}

private enum AcademicRecordsError: LocalizedError {
    case invalidResponse
    case remote(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "无法解析教务系统返回的数据。"
        case .remote(let message): message
        }
    }
}

