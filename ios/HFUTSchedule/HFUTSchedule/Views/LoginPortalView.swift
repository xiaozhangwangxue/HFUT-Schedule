import SwiftUI

struct LoginPortalView: View {
    @EnvironmentObject private var scheduleStore: ScheduleStore
    @EnvironmentObject private var recordsStore: AcademicRecordsStore
    @EnvironmentObject private var studentStore: AcademicStudentStore
    @EnvironmentObject private var notificationManager: CourseNotificationManager
    @Environment(\.dismiss) private var dismiss
    @AppStorage("academicConnectionMode") private var connectionMode = AcademicConnectionMode.direct.rawValue
    @State private var isSyncing = false
    @State private var syncMessage = "登录成功后将自动同步学籍、课表、成绩与考试"
    @State private var resultMessage: String?

    private var selectedMode: AcademicConnectionMode {
        AcademicConnectionMode(rawValue: connectionMode) ?? .direct
    }

    var body: some View {
        Group {
            if selectedMode == .direct {
                NativeCASLoginView(onAuthenticated: synchronizeAll)
            } else {
                PortalWebView(
                    url: AcademicPortal.loginURL(for: selectedMode),
                    academicMode: selectedMode,
                    onAcademicAuthenticated: synchronizeAll
                )
            }
        }
            .id(selectedMode)
            .safeAreaInset(edge: .top) {
                Picker("访问方式", selection: $connectionMode) {
                    ForEach(AcademicConnectionMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 14)
                .padding(.top, 6)
            }
            .safeAreaInset(edge: .bottom) {
                Label(isSyncing ? "正在同步教务数据…" : syncMessage, systemImage: isSyncing ? "arrow.triangle.2.circlepath" : "lock.shield.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .adaptiveGlass(cornerRadius: 19)
                    .padding(.bottom, 6)
            }
            .navigationTitle("安全登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .alert("统一身份认证", isPresented: Binding(
                get: { resultMessage != nil },
                set: { if !$0 { resultMessage = nil } }
            )) {
                Button("完成") { dismiss() }
                Button("留在此页", role: .cancel) { resultMessage = nil }
            } message: {
                Text(resultMessage ?? "")
            }
    }

    private func synchronizeAll(cookies: [HTTPCookie]) {
        guard !isSyncing else { return }
        isSyncing = true
        syncMessage = "正在读取本学期教务数据"
        let mode = selectedMode
        Task {
            let client = AcademicClient(mode: mode, cookies: cookies)
            var completed: [String] = []
            var failures: [String] = []

            do {
                let info = try await client.fetchStudentInfo()
                await MainActor.run { studentStore.replace(with: info) }
                completed.append("学籍")
            } catch { failures.append("学籍：\(error.localizedDescription)") }

            do {
                let schedule = try await client.fetchSchedule(semesterID: AcademicPortal.currentSemesterID)
                await MainActor.run {
                    scheduleStore.replaceAcademicCourses(with: schedule.courses())
                }
                try? await notificationManager.reschedule(for: scheduleStore.courses)
                completed.append("课表")
            } catch { failures.append("课表：\(error.localizedDescription)") }

            do {
                let grades = try await client.fetchGrades()
                await MainActor.run { recordsStore.replaceGrades(with: grades) }
                completed.append("成绩")
            } catch { failures.append("成绩：\(error.localizedDescription)") }

            do {
                let exams = try await client.fetchExams()
                await MainActor.run { recordsStore.replaceExams(with: exams) }
                completed.append("考试")
            } catch { failures.append("考试：\(error.localizedDescription)") }

            await MainActor.run {
                isSyncing = false
                if failures.isEmpty {
                    syncMessage = "教务数据已同步"
                    resultMessage = "登录成功，已自动同步\(completed.joined(separator: "、"))。"
                } else {
                    syncMessage = completed.isEmpty ? "自动同步失败，可重试登录" : "部分教务数据已同步"
                    let successText = completed.isEmpty ? "" : "已同步：\(completed.joined(separator: "、"))\n\n"
                    resultMessage = successText + failures.joined(separator: "\n")
                }
            }
        }
    }
}
