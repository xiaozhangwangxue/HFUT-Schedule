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
    @State private var usesWebLoginFallback = false

    private var selectedMode: AcademicConnectionMode {
        AcademicConnectionMode(rawValue: connectionMode) ?? .direct
    }

    var body: some View {
        Group {
            if usesWebLoginFallback {
                PortalWebView(
                    url: AcademicPortal.loginURL(for: selectedMode),
                    academicMode: selectedMode,
                    onAcademicAuthenticated: synchronizeFromWebLogin
                )
            } else {
                NativeCASLoginView(
                    mode: selectedMode,
                    onAuthenticated: synchronizeAll,
                    onPreparationFailure: recoverFromPreparationFailure
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button(
                        usesWebLoginFallback ? "原生登录" : "网页登录",
                        systemImage: usesWebLoginFallback ? "bolt.horizontal.circle" : "safari"
                    ) {
                        usesWebLoginFallback.toggle()
                        syncMessage = usesWebLoginFallback
                            ? "请在校方页面登录，完成后将自动同步"
                            : "正在获取原生 CAS 登录参数"
                    }
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

    private func synchronizeAll(cookies: [HTTPCookie], username: String, password: String) {
        guard !isSyncing else { return }
        CampusSessionStore.shared.persist(cookies)
        isSyncing = true
        syncMessage = "正在读取本学期教务数据"
        let mode = selectedMode
        Task {
            let client = AcademicClient(mode: mode, cookies: cookies)
            var completed: [String] = []
            var failures: [String] = []
            var syncedStudentInfo: AcademicStudentInfo?
            var gradesSynced = false
            var examsSynced = false

            do {
                let info = try await client.fetchStudentInfo()
                syncedStudentInfo = info
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
                gradesSynced = true
            } catch { failures.append("成绩：\(error.localizedDescription)") }

            do {
                let exams = try await client.fetchExams()
                await MainActor.run { recordsStore.replaceExams(with: exams) }
                completed.append("考试")
                examsSynced = true
            } catch { failures.append("考试：\(error.localizedDescription)") }

            let uniAppUsername = username.isEmpty ? (syncedStudentInfo?.studentID ?? "") : username
            if !uniAppUsername.isEmpty {
                var uniAppError: Error?
                var uniAppLoggedIn = OfficialCampusAPIClient.shared.hasUniAppToken
                if !uniAppLoggedIn {
                    do {
                        _ = try await OfficialCampusAPIClient.shared.ensureUniAppLogin(
                            studentInfo: syncedStudentInfo,
                            username: uniAppUsername
                        )
                        uniAppError = nil
                        uniAppLoggedIn = true
                        completed.append("合工大教务 API")
                    } catch {
                        uniAppError = error
                    }
                }
                if !uniAppLoggedIn, let uniAppError {
                    failures.append("合工大教务 API：\(uniAppError.localizedDescription)")
                }

                if uniAppLoggedIn, !gradesSynced {
                    do {
                        let grades = try await OfficialCampusAPIClient.shared.fetchGrades()
                        await MainActor.run { recordsStore.replaceGrades(with: grades) }
                        completed.append("成绩（官方 API）")
                        gradesSynced = true
                        failures.removeAll { $0.hasPrefix("成绩：") }
                    } catch {
                        failures.append("成绩（官方 API）：\(error.localizedDescription)")
                    }
                }
                if uniAppLoggedIn, !examsSynced {
                    do {
                        let exams = try await OfficialCampusAPIClient.shared.fetchExams()
                        await MainActor.run { recordsStore.replaceExams(with: exams) }
                        completed.append("考试（官方 API）")
                        examsSynced = true
                        failures.removeAll { $0.hasPrefix("考试：") }
                    } catch {
                        failures.append("考试（官方 API）：\(error.localizedDescription)")
                    }
                }
            }

            do {
                _ = try await OfficialCampusAPIClient.shared.refreshCommunityToken()
                completed.append("智慧社区 API")
            } catch {
                failures.append("智慧社区 API：\(error.localizedDescription)")
            }

            do {
                _ = try await CampusServiceClient.shared.refreshHuiXinToken()
                completed.append("一卡通与生活缴费")
            } catch {
                failures.append("一卡通：\(error.localizedDescription)")
            }

            do {
                _ = try await CampusServiceClient.shared.fetchSecondClassActivities()
                completed.append("第二课堂")
            } catch {
                failures.append("第二课堂：\(error.localizedDescription)")
            }

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

    private func recoverFromPreparationFailure(_ error: Error) {
        guard isConnectivityFailure(error) else { return }
        if selectedMode == .direct {
            syncMessage = "原生直连不可达，已切换 WebVPN 安全登录"
            connectionMode = AcademicConnectionMode.webVPN.rawValue
            usesWebLoginFallback = false
        } else {
            syncMessage = "原生请求不可达，已切换 WebVPN 网页安全登录"
            usesWebLoginFallback = true
        }
    }

    private func synchronizeFromWebLogin(_ cookies: [HTTPCookie]) {
        synchronizeAll(cookies: cookies, username: "", password: "")
    }

    private func isConnectivityFailure(_ error: Error) -> Bool {
        let code = (error as? URLError)?.code
            ?? ((error as NSError).domain == NSURLErrorDomain ? URLError.Code(rawValue: (error as NSError).code) : nil)
        return [
            .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
            .notConnectedToInternet, .dnsLookupFailed, .secureConnectionFailed
        ].contains(code)
    }

}
