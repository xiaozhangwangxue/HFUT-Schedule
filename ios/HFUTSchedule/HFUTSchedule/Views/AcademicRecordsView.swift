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
    @State private var showingGradeRemark = false
    @State private var gradeQuery = ""
    @State private var compactGrades = false

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
            if kind == .grades {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("成绩说明", systemImage: "info.circle") { showingGradeRemark = true }
                    Button(compactGrades ? "展开明细" : "紧凑显示", systemImage: compactGrades ? "list.bullet" : "rectangle.compress.vertical") {
                        compactGrades.toggle()
                    }
                }
            }
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
        .sheet(isPresented: $showingGradeRemark) { GradeRemarkView() }
    }

    @ViewBuilder
    private var gradesContent: some View {
        if store.gradeTerms.isEmpty {
            emptyContent(description: "登录教务系统后同步历学期成绩，数据会保存在本机。")
        } else {
            List {
                Section("成绩分析") {
                    SourceAnchoredNavigationLink(sourceID: "grades-analysis") {
                        GradeAnalysisView(grades: visibleTerms.flatMap(\.grades))
                    } label: {
                        HStack {
                            Label("平均成绩", systemImage: "chart.line.uptrend.xyaxis")
                            Spacer()
                            Text(analysisSummary)
                                .font(.headline.monospacedDigit())
                        }
                    }
                }
                ForEach(visibleTerms) { term in
                    Section(term.term) {
                        ForEach(sortedGrades(term.grades)) { grade in
                            SourceAnchoredNavigationLink(sourceID: "grade-\(term.id)-\(grade.id)") {
                                GradeDetailView(grade: grade)
                            } label: {
                                GradeRow(grade: grade, compact: compactGrades)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .searchable(text: $gradeQuery, prompt: "搜索 课程名、代码")
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

    private var visibleTerms: [AcademicGradeTerm] {
        let query = gradeQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.gradeTerms.compactMap { term in
            let grades = term.grades.filter {
                query.isEmpty || "\($0.courseName) \($0.lessonCode)".localizedCaseInsensitiveContains(query)
            }
            return grades.isEmpty ? nil : AcademicGradeTerm(term: term.term, grades: grades)
        }
    }

    private func sortedGrades(_ grades: [AcademicGrade]) -> [AcademicGrade] {
        grades.sorted {
            let lhsFailed = (Double($0.score) ?? 100) < 60
            let rhsFailed = (Double($1.score) ?? 100) < 60
            return lhsFailed == rhsFailed ? $0.courseName < $1.courseName : lhsFailed
        }
    }

    private var analysisSummary: String {
        let grades = visibleTerms.flatMap(\.grades)
        let score = GradeStatistics.weightedScore(grades)
        let gpa = GradeStatistics.weightedGPA(grades)
        if let score, let gpa { return "\(score.formatted(.number.precision(.fractionLength(2)))) | \(gpa.formatted(.number.precision(.fractionLength(2))))" }
        return "查看分析"
    }
}

private struct GradeRow: View {
    let grade: AcademicGrade
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(grade.courseName)
                        .font(.headline)
                    Text([grade.lessonCode, "\(grade.credits) 学分", "绩点 \(grade.gpa)"].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if compact, !grade.detail.isEmpty {
                        Text(grade.detail)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Image(systemName: isFailed ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(isFailed ? .red : .secondary)
                Text(grade.score)
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(scoreColor)
            }
            if !compact, !detailComponents.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(detailComponents.enumerated()), id: \.offset) { _, text in
                            Text(text)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(.secondary.opacity(0.12), in: Capsule())
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var detailComponents: [String] {
        grade.detail.split(separator: " ").map(String.init)
    }

    private var isFailed: Bool { (Double(grade.score) ?? 100) < 60 }

    private var scoreColor: Color {
        guard let value = Double(grade.score) else { return .primary }
        return value < 60 ? .red : .primary
    }
}

private enum GradeStatistics {
    static func weightedScore(_ grades: [AcademicGrade]) -> Double? {
        weighted(grades) { Double($0.score) }
    }

    static func weightedGPA(_ grades: [AcademicGrade]) -> Double? {
        weighted(grades) { Double($0.gpa) }
    }

    static func totalCredits(_ grades: [AcademicGrade]) -> Double {
        grades.compactMap { Double($0.credits) }.reduce(0, +)
    }

    private static func weighted(_ grades: [AcademicGrade], value: (AcademicGrade) -> Double?) -> Double? {
        let pairs = grades.compactMap { grade -> (Double, Double)? in
            guard let metric = value(grade), let credits = Double(grade.credits), credits > 0 else { return nil }
            return (metric, credits)
        }
        let credits = pairs.reduce(0) { $0 + $1.1 }
        guard credits > 0 else { return nil }
        return pairs.reduce(0) { $0 + $1.0 * $1.1 } / credits
    }
}

private struct GradeAnalysisView: View {
    let grades: [AcademicGrade]

    var body: some View {
        List {
            Section("总览") {
                LabeledContent("课程数", value: "\(grades.count) 门")
                LabeledContent("总学分", value: GradeStatistics.totalCredits(grades).formatted(.number.precision(.fractionLength(0...2))))
                LabeledContent("平均成绩", value: GradeStatistics.weightedScore(grades)?.formatted(.number.precision(.fractionLength(2))) ?? "--")
                LabeledContent("平均绩点", value: GradeStatistics.weightedGPA(grades)?.formatted(.number.precision(.fractionLength(2))) ?? "--")
                LabeledContent("未通过", value: "\(grades.filter { (Double($0.score) ?? 100) < 60 }.count) 门")
            }
        }
        .navigationTitle("成绩分析")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct GradeDetailView: View {
    let grade: AcademicGrade

    private var detailItems: [(String, String)] {
        grade.detail.split(separator: " ").map { component in
            let parts = component.split(separator: ":", maxSplits: 1).map(String.init)
            return (parts.first ?? String(component), parts.count > 1 ? parts[1] : "")
        }
    }

    var body: some View {
        List {
            Section("课程成绩") {
                LabeledContent("最终成绩", value: grade.score)
                LabeledContent("绩点", value: grade.gpa)
                LabeledContent("学分", value: grade.credits)
                LabeledContent("课程代码", value: grade.lessonCode)
            }
            if !detailItems.isEmpty {
                Section("成绩组成") {
                    ForEach(Array(detailItems.enumerated()), id: \.offset) { _, item in
                        LabeledContent(item.0, value: item.1.isEmpty ? "--" : item.1)
                    }
                }
            }
        }
        .navigationTitle(grade.courseName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct GradeRemarkView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("数据来源") {
                    Text("成绩页优先使用合工大教务 API，安全登录后会自动同步，并将最近一次结果保存在本机。")
                }
                Section("计算方式") {
                    Text("平均成绩和平均绩点均按课程学分加权；未返回数字成绩或有效学分的课程不参与对应平均值计算。")
                }
            }
            .navigationTitle("成绩说明")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("完成") { dismiss() } }
        }
        .presentationDetents([.medium, .large])
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
