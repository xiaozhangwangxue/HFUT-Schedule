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
    @AppStorage("academicConnectionMode") private var connectionMode = AcademicConnectionMode.direct.rawValue

    private var selectedMode: AcademicConnectionMode {
        AcademicConnectionMode(rawValue: connectionMode) ?? .direct
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                AcademicRecordsWebView(
                    kind: kind,
                    syncTrigger: syncTrigger,
                    connectionMode: selectedMode,
                    onPageReady: {
                        guard !pageReady else { return }
                        pageReady = true
                        status = "登录完成，正在自动同步\(kind.title)…"
                        isSyncing = true
                        syncTrigger += 1
                    },
                    onResult: handleResult
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
    let connectionMode: AcademicConnectionMode
    let onPageReady: () -> Void
    let onResult: (Result<AcademicRecordsPayload, Error>) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 HFUTSchedule-iOS"

        webView.load(URLRequest(url: AcademicPortal.loginURL(for: connectionMode)))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        guard syncTrigger > context.coordinator.lastSyncTrigger else { return }
        context.coordinator.lastSyncTrigger = syncTrigger
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            Task {
                do {
                    let client = AcademicClient(mode: connectionMode, cookies: cookies)
                    let payload: AcademicRecordsPayload
                    switch kind {
                    case .grades:
                        payload = AcademicRecordsPayload(grades: try await client.fetchGrades(), exams: [])
                    case .exams:
                        payload = AcademicRecordsPayload(grades: [], exams: try await client.fetchExams())
                    }
                    await MainActor.run { onResult(.success(payload)) }
                } catch {
                    await MainActor.run { onResult(.failure(error)) }
                }
            }
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: AcademicRecordsWebView
        var lastSyncTrigger = 0
        private var enteredAcademicAfterVPNLogin = false

        init(parent: AcademicRecordsWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
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
