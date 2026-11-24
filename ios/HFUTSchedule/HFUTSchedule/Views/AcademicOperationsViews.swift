import SwiftUI

private var currentAcademicClient: AcademicClient {
    let mode = AcademicConnectionMode(rawValue: UserDefaults.standard.string(forKey: "academicConnectionMode") ?? "") ?? .direct
    return AcademicClient(mode: mode, cookies: CampusSessionStore.shared.allCookies)
}

struct AcademicProgramProgressView: View {
    @State private var details: ProgramProgressDetails?
    @State private var error: String?
    @State private var filter = "全部"
    var body: some View {
        List {
            Picker("修读状态", selection: $filter) { ForEach(["全部", "已修", "在修", "未修", "挂科"], id: \.self) { Text($0) } }
            if let error { Text(error).foregroundStyle(.red) }
            if let details {
                ForEach(details.moduleList) { module in
                    Section(module.nameZh) { ProgressModuleRows(module: module, filter: filter) }
                }
                Section("培养方案外课程") {
                    ForEach(details.outerCourseList.filter { filter == "全部" || $0.status == filter }) { ProgressCourseRow(course: $0) }
                }
            } else if error == nil { ProgressView("正在读取修读状态…") }
        }
        .navigationTitle("培养方案完成情况")
        .task { await load() }.refreshable { await load() }
    }
    @MainActor private func load() async {
        error = nil
        do { details = try await currentAcademicClient.fetchProgramProgressDetails() } catch { AcademicServiceDiagnostics.record(context: "学业业务操作", error: error); self.error = error.localizedDescription }
    }
}
private struct ProgressModuleRows: View {
    let module: ProgramProgressModule
    let filter: String
    var body: some View {
        ForEach(module.allCourseList.filter { filter == "全部" || $0.status == filter }) { ProgressCourseRow(course: $0) }
        ForEach(module.allModuleList) { child in
            DisclosureGroup(child.nameZh) { AnyView(ProgressModuleRows(module: child, filter: filter)) }
        }
    }
}
private struct ProgressCourseRow: View {
    let course: ProgramProgressCourse
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack { Text(course.nameZh); Spacer(); Text(course.status).foregroundStyle(course.resultType == "FAILED" ? .red : .secondary) }
            Text("\(course.code) · \(course.credits.formatted()) 学分 · \(course.compulsory ? "必修" : "选修")").font(.caption).foregroundStyle(.secondary)
            if let score = course.score { Text("成绩 \(score.formatted()) · 绩点 \(course.gp?.formatted() ?? "--")").font(.caption) }
            if let rank = course.rank { Text(rank).font(.caption) }
        }
    }
}

struct AllAcademicProgramsView: View {
    @State private var keyword = ""
    @State private var page = 1
    @State private var items: [AcademicProgramSearchItem] = []
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        List {
            Section {
                TextField("方案名称", text: $keyword)
                Button("搜索") { page = 1; Task { await load() } }.disabled(loading)
            }
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(items) { item in
                AppNavigationLink { OtherAcademicProgramView(programID: item.id, title: item.nameZh) } label: {
                    VStack(alignment: .leading) { Text(item.nameZh); Text([item.grade, item.department.nameZh ?? "", item.major.nameZh ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
                }
            }
            AcademicPageControls(page: $page, loading: loading)
        }
        .navigationTitle("全校培养方案")
        .task(id: page) { await load() }
        .overlay { if loading { ProgressView() } }
    }
    @MainActor private func load() async {
        loading = true; error = nil; defer { loading = false }
        do { items = try await OfficialCampusAPIClient.shared.searchAcademicPrograms(keyword: keyword, page: page) } catch { AcademicServiceDiagnostics.record(context: "学业业务操作", error: error); self.error = error.localizedDescription }
    }
}
private struct OtherAcademicProgramView: View {
    let programID: Int
    let title: String
    @State private var node: AcademicProgramNode?
    @State private var selectedCourse: AcademicProgramCourse?
    @State private var error: String?
    var body: some View {
        Group {
            if let node { ProgramModuleView(node: node, selectedCourse: $selectedCourse) }
            else if let error { ContentUnavailableView("读取失败", systemImage: "exclamationmark.triangle", description: Text(error)) }
            else { ProgressView() }
        }
        .navigationTitle(title)
        .sheet(item: $selectedCourse) { ProgramCourseDetailSheet(course: $0) }
        .task { do { node = try await OfficialCampusAPIClient.shared.academicProgram(id: programID) } catch { AcademicServiceDiagnostics.record(context: "学业业务操作", error: error); self.error = error.localizedDescription } }
    }
}
struct AcademicCourseConfirmationView: View {
    @State private var items: [String: [AcademicConfirmedCourse]] = [:]
    @State private var error: String?
    @State private var loaded = false
    private let names = ["CURRENT_SEMESTER": "本学期漏选必修课程", "HISTORY_SEMESTER": "历史学期漏选必修课程", "NAVER_NOT_PASSED": "未通过必修课程"]
    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(items.keys.sorted(), id: \.self) { key in
                Section(names[key] ?? key) {
                    ForEach(items[key] ?? []) { course in
                        VStack(alignment: .leading) { Text(course.courseName); Text("\(course.courseCode) · \(course.credits.formatted()) 学分").font(.caption).foregroundStyle(.secondary) }
                    }
                    if items[key]?.isEmpty == true { Text("无相关课程").foregroundStyle(.secondary) }
                }
            }
            if !loaded { ProgressView() }
            if loaded && items.isEmpty && error == nil { Text("校方没有返回待确认课程。") }
        }
        .navigationTitle("选课与学分确认")
        .task { await load() }.refreshable { await load() }
    }
    @MainActor private func load() async {
        error = nil; defer { loaded = true }
        do { items = try await currentAcademicClient.fetchCourseConfirmation(semesterID: AcademicPortal.currentSemesterID) } catch { AcademicServiceDiagnostics.record(context: "学业业务操作", error: error); self.error = error.localizedDescription }
    }
}

struct AcademicPageControls: View {
    @Binding var page: Int
    let loading: Bool
    var body: some View {
        HStack {
            Button("上一页") { page -= 1 }.disabled(page <= 1 || loading)
            Spacer(); Text("第 \(page) 页").font(.caption.monospacedDigit()); Spacer()
            Button("下一页") { page += 1 }.disabled(loading)
        }
    }
}

struct AcademicSurveyFormView: View {
    let taskID: Int
    let teacher: String
    @State private var form: AcademicSurveyForm?
    @State private var choices: [String: String] = [:]
    @State private var comments: [String: String] = [:]
    @State private var error: String?
    @State private var loading = false
    @State private var submitted = false
    @State private var confirmSubmit = false
    @State private var awaitingConfirmation = false
    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            if submitted { Label("评教已提交", systemImage: "checkmark.circle.fill") }
            if let form, !submitted {
                Section("批量选择") {
                    Menu("按分值统一选择") {
                        Button("全部最高分选项") { choose(form, highest: true) }
                        Button("全部最低分选项") { choose(form, highest: false) }
                    }
                }
                ForEach(form.survey.radioQuestions) { question in
                    Section(AcademicHTMLText.clean(question.title)) {
                        ForEach(question.options, id: \.name) { option in
                            Button { choices[question.id] = option.name } label: {
                                HStack { Text(option.name); Spacer(); Text("\(option.score) 分").font(.caption); if choices[question.id] == option.name { Image(systemName: "checkmark") } }
                            }
                        }
                    }
                }
                ForEach(form.survey.blankQuestions) { question in
                    Section(AcademicHTMLText.clean(question.title)) { TextField("填写评价", text: Binding(get: { comments[question.id] ?? "" }, set: { comments[question.id] = $0 }), axis: .vertical).lineLimit(3...6) }
                }
                if awaitingConfirmation {
                    Button("刷新提交状态", systemImage: "arrow.clockwise") { Task { await confirmStatus() } }.disabled(loading)
                }
                Button("提交评教", systemImage: "paperplane") { confirmSubmit = true }.disabled(loading || awaitingConfirmation || choices.count != form.survey.radioQuestions.count)
            }
        }
        .navigationTitle(teacher)
        .overlay { if loading { ProgressView() } }
        .task { await load() }
        .confirmationDialog("提交对\(teacher)的评教？", isPresented: $confirmSubmit, titleVisibility: .visible) { Button("确认提交") { Task { await submit() } } }
    }
    private func choose(_ form: AcademicSurveyForm, highest: Bool) {
        for question in form.survey.radioQuestions {
            choices[question.id] = question.options.sorted { highest ? $0.score > $1.score : $0.score < $1.score }.first?.name
        }
    }
    @MainActor private func load() async {
        loading = true; defer { loading = false }
        do { form = try await currentAcademicClient.fetchSurveyForm(taskID: taskID) } catch { AcademicServiceDiagnostics.record(context: "学业业务操作", error: error); self.error = error.localizedDescription }
    }
    @MainActor private func submit() async {
        guard let form else { return }; loading = true; error = nil; defer { loading = false }
        do { try await currentAcademicClient.submitSurvey(taskID: taskID, form: form, choices: choices, comments: comments); submitted = true }
        catch AcademicWorkflowError.surveyUnconfirmed(let detail) {
            awaitingConfirmation = true
            error = AcademicWorkflowError.surveyUnconfirmed(detail).localizedDescription
        } catch { AcademicServiceDiagnostics.record(context: "学业业务操作", error: error); self.error = error.localizedDescription }
    }
    @MainActor private func confirmStatus() async {
        loading = true; error = nil; defer { loading = false }
        do { try await currentAcademicClient.confirmSurveySubmission(taskID: taskID); submitted = true; awaitingConfirmation = false }
        catch { AcademicServiceDiagnostics.record(context: "学业业务操作", error: error); self.error = "校方结果仍未确认，答卷已保留。\(error.localizedDescription)" }
    }
}

struct AcademicBulkSurveyView: View {
    let lessons: [AcademicSurveyLesson]
    @State private var results: [AcademicBulkSurveyResult] = []
    @State private var comment = "好"
    @State private var running = false
    @State private var confirming = false
    @State private var worker: Task<Void, Never>?
    private let savedKey = "academicBulkSurveyResults"
    private var confirmedCount: Int { results.filter { $0.status == .confirmed }.count }
    private var retryableCount: Int { results.filter { $0.status == .waiting || $0.status == .failed }.count }
    var body: some View {
        List {
            Section("批量评教设置") {
                Text("为每道单选题选择分值最高的选项，以下文字用于各问卷的填写题。每份问卷均回读校方状态后才计为完成。")
                    .font(.footnote).foregroundStyle(.secondary)
                TextField("统一文字评价", text: $comment, axis: .vertical).disabled(running)
                Button("确认并提交全部待评教师") { confirming = true }.disabled(running || retryableCount == 0)
                if running { Button("停止后续提交", role: .destructive) { worker?.cancel() } }
            }
            Section("逐项结果") {
                Text("已确认 \(confirmedCount) / \(results.count)")
                ProgressView(value: Double(confirmedCount), total: Double(max(1, results.count)))
                if AcademicBulkSurveyResult.allConfirmed(results) { Label("本批次均已由校方确认", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                ForEach(results) { result in
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(result.teacher) · \(result.course)").font(.headline)
                        Text(result.message).font(.caption).foregroundStyle(result.status == .confirmed ? .secondary : .primary)
                        if result.status == .unconfirmed {
                            Button("只刷新此项提交状态") { Task { await refresh(result.id) } }.disabled(running)
                        }
                        if result.status == .failed || result.status == .unconfirmed {
                            AppNavigationLink("打开问卷核对") { AcademicSurveyFormView(taskID: result.id, teacher: result.teacher) }.disabled(running)
                        }
                    }.padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("全部教师评教")
        .task { restoreResults() }
        .confirmationDialog("将按最高分选项与所填评价逐份提交给\(retryableCount)位教师，确认继续？", isPresented: $confirming, titleVisibility: .visible) {
            Button("确认提交") { worker = Task { await run() } }
        }
        .onDisappear { worker?.cancel() }
    }
    private func restoreResults() {
        guard results.isEmpty else { return }
        let saved = UserDefaults.standard.data(forKey: savedKey).flatMap { try? JSONDecoder().decode([AcademicBulkSurveyResult].self, from: $0) } ?? []
        var seen = Set<Int>()
        results = lessons.flatMap { lesson in lesson.teachers.filter { !$0.submitted }.map { teacher in
            var value = saved.first { $0.id == teacher.id } ?? AcademicBulkSurveyResult(id: teacher.id, teacher: teacher.name, course: lesson.courseName)
            if value.status == .running { value.status = .unconfirmed; value.message = "上次提交被中断，需回读校方状态" }
            if value.status == .confirmed { value.status = .unconfirmed; value.message = "当前校方列表尚未确认，需重新读取提交状态" }
            return value
        } }.filter { seen.insert($0.id).inserted }
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(results) { UserDefaults.standard.set(data, forKey: savedKey) }
    }
    private func setResult(_ id: Int, status: AcademicBulkSurveyResult.Status, message: String) {
        guard let index = results.firstIndex(where: { $0.id == id }) else { return }
        results[index].status = status; results[index].message = message; persist()
    }
    @MainActor private func run() async {
        guard !running else { return }; running = true
        defer { running = false; worker = nil; persist() }
        let selected = results.filter { $0.status == .waiting || $0.status == .failed }
        let chosenComment = comment
        for result in selected {
            if Task.isCancelled { break }
            setResult(result.id, status: .running, message: "正在获取问卷")
            var sent = false
            do {
                let form = try await currentAcademicClient.fetchSurveyForm(taskID: result.id)
                let draft = try AcademicSurveyDraft.highest(form: form, comment: chosenComment)
                try Task.checkCancellation()
                setResult(result.id, status: .running, message: "正在提交并核对校方结果")
                sent = true
                try await currentAcademicClient.submitSurvey(taskID: result.id, form: form, choices: draft.choices, comments: draft.comments)
                setResult(result.id, status: .confirmed, message: "校方已确认提交")
            } catch AcademicWorkflowError.surveyUnconfirmed(let detail) {
                setResult(result.id, status: .unconfirmed, message: "请求已发送，结果待确认：\(detail)")
            } catch is CancellationError {
                setResult(result.id, status: sent ? .unconfirmed : .waiting, message: sent ? "已停止；该请求结果需回读校方确认" : "已停止，尚未提交")
                break
            } catch { AcademicServiceDiagnostics.record(context: "学业业务操作", error: error);
                // A transport failure after sending may still have reached the
                // server. Keep it out of automatic retries until checked.
                setResult(result.id, status: sent ? .unconfirmed : .failed, message: error.localizedDescription)
            }
        }
    }
    @MainActor private func refresh(_ id: Int) async {
        guard !running else { return }; running = true; defer { running = false }
        do { try await currentAcademicClient.confirmSurveySubmission(taskID: id); setResult(id, status: .confirmed, message: "校方已确认提交") }
        catch { AcademicServiceDiagnostics.record(context: "学业业务操作", error: error); setResult(id, status: .unconfirmed, message: "结果尚未确认：\(error.localizedDescription)") }
    }
}

struct AcademicSchedulePreviewView: View {
    let courses: [Course]
    var title = "课程时间与冲突"
    @State private var week = 1
    @State private var selected: Course?
    private var maximumWeek: Int { max(20, courses.flatMap { $0.weekIndices ?? [] }.max() ?? 20) }
    var body: some View {
        ScrollView {
            Stepper("第 \(week) 周", value: $week, in: 1...maximumWeek).padding()
            TimetableGridView(courses: courses.filter { $0.weekIndices?.contains(week) ?? true }, visibleWeekdays: Array(1...7), week: week, termStart: ScheduleCalendar.termStart(from: courses)) { selected = $0 }
            if courses.isEmpty { Text("课程暂无排课时间").foregroundStyle(.secondary) }
        }
        .navigationTitle(title)
        .sheet(item: $selected) { course in AppNavigationStack { CourseDetailView(course: course) } }
    }
}

struct AcademicSelectionScheduleView: View {
    let turnID: Int
    var candidateID: Int? = nil
    @State private var courses: [Course]?
    @State private var error: String?
    var body: some View {
        Group {
            if let courses { AcademicSchedulePreviewView(courses: courses) }
            else if let error { ContentUnavailableView("课表读取失败", systemImage: "calendar.badge.exclamationmark", description: Text(error)) }
            else { ProgressView("正在读取已选课程排课…") }
        }
        .task {
            do {
                let selected = try await currentAcademicClient.fetchSelectedLessons(turnID: turnID)
                let ids = Array(Set(selected.map(\.id) + (candidateID.map { [$0] } ?? [])))
                courses = try await currentAcademicClient.lessonSchedule(lessonIDs: ids)
            } catch { AcademicServiceDiagnostics.record(context: "学业业务操作", error: error); self.error = error.localizedDescription }
        }
    }
}

struct AcademicTransferView: View {
    @State private var batches: [TransferBatch] = []
    @State private var hiddenID = ""
    @State private var error: String?
    var body: some View {
        List {
            Section("隐藏批次") {
                TextField("批次代号", text: $hiddenID).keyboardType(.numberPad)
                if !hiddenID.isEmpty { AppNavigationLink("进入批次 \(hiddenID)") { AcademicTransferBatchView(batchID: hiddenID, title: "批次 \(hiddenID)") } }
            }
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(batches) { batch in
                AppNavigationLink { AcademicTransferBatchView(batchID: batch.batchID, title: batch.title) } label: {
                    VStack(alignment: .leading, spacing: 4) { Text(batch.title); Text([batch.applicationDate, batch.admissionDate].joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
        .navigationTitle("转专业")
        .task { await load() }.refreshable { await load() }
    }
    @MainActor private func load() async { do { batches = try await currentAcademicClient.fetchTransferBatches() } catch { AcademicServiceDiagnostics.record(context: "学业业务操作", error: error); self.error = error.localizedDescription } }
}
private struct AcademicTransferBatchView: View {
    let batchID: String
    let title: String
    @State private var items: [TransferApplication] = []
    @State private var myItems: [TransferMyApply] = []
    @State private var query = ""
    @State private var error: String?
    @State private var cancellation: TransferMyApply?
    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            Section("我的申请") {
                ForEach(myItems) { item in
                    AppNavigationLink { AcademicTransferDetailsView(applicationID: item.id) } label: {
                        VStack(alignment: .leading) { Text(item.major); Text("\(item.department) · \(item.status)").font(.caption).foregroundStyle(.secondary) }
                    }
                    .swipeActions { Button("撤销申请", role: .destructive) { cancellation = item } }
                }
                if myItems.isEmpty { Text("暂无申请").foregroundStyle(.secondary) }
            }
            Section("可申请专业") {
                ForEach(items.filter { query.isEmpty || "\($0.major) \($0.department)".localizedCaseInsensitiveContains(query) }) { item in
                    AppNavigationLink { AcademicTransferApplyView(batchID: batchID, item: item, didSubmit: { Task { await load() } }) } label: {
                        VStack(alignment: .leading, spacing: 4) { Text(item.major); Text(item.department).font(.caption); Text("计划 \(item.preparedCount) · 已申请 \(item.applyCount)").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        }
        .navigationTitle(title).searchable(text: $query, prompt: "学院或专业")
        .task { await load() }.refreshable { await load() }
        .confirmationDialog("确认撤销\(cancellation?.major ?? "")申请？", isPresented: Binding(get: { cancellation != nil }, set: { if !$0 { cancellation = nil } }), titleVisibility: .visible) {
            Button("撤销申请", role: .destructive) { if let item = cancellation { Task { await cancel(item) } } }
        }
    }
    @MainActor private func load() async {
        error = nil
        do { async let values = currentAcademicClient.fetchTransferApplications(batchID: batchID); async let mine = currentAcademicClient.fetchMyTransferApplications(batchID: batchID); (items, myItems) = try await (values, mine) } catch { AcademicServiceDiagnostics.record(context: "学业业务操作", error: error); self.error = error.localizedDescription }
    }
    @MainActor private func cancel(_ item: TransferMyApply) async {
        do { try await currentAcademicClient.cancelTransfer(batchID: batchID, applicationID: item.id); await load() } catch { AcademicServiceDiagnostics.record(context: "学业业务操作", error: error); self.error = error.localizedDescription }
        cancellation = nil
    }
}
private struct AcademicTransferApplyView: View {
    let batchID: String
    let item: TransferApplication
    let didSubmit: () -> Void
    @State private var telephone = ""
    @State private var email = ""
    @State private var remark = ""
    @State private var confirm = false
    @State private var loading = false
    @State private var message: String?
    var body: some View {
        Form {
            Section("申请专业") { LabeledContent("专业", value: item.major); LabeledContent("学院", value: item.department); Text(item.conditions); Text("\(item.applyStart) 至 \(item.applyEnd)").font(.caption) }
            Section("联系方式与材料") {
                TextField("联系电话（必填）", text: $telephone).keyboardType(.phonePad)
                TextField("邮箱", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                TextField("申请备注", text: $remark, axis: .vertical)
            }
            if let message { Text(message) }
            Button("提交转专业申请") { confirm = true }.disabled(loading || telephone.isEmpty)
        }
        .navigationTitle(item.major)
        .overlay { if loading { ProgressView() } }
        .confirmationDialog("确认申请\(item.major)？", isPresented: $confirm, titleVisibility: .visible) { Button("确认提交") { Task { await submit() } } }
    }
    @MainActor private func submit() async {
        loading = true; defer { loading = false }
        do { let result = try await currentAcademicClient.submitTransfer(batchID: batchID, submitID: item.id, telephone: telephone, email: email, remark: remark); message = result.message; if result.success { didSubmit() } } catch { AcademicServiceDiagnostics.record(context: "学业业务操作", error: error); message = error.localizedDescription }
    }
}
private struct AcademicTransferDetailsView: View {
    let applicationID: Int
    @State private var fields: [AcademicDetailField] = []
    @State private var error: String?
    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(fields) { field in LabeledContent(field.label, value: field.value).textSelection(.enabled) }
        }
        .navigationTitle("申请详情与考核成绩")
        .task { do { fields = try await currentAcademicClient.transferDetails(applicationID: applicationID) } catch { AcademicServiceDiagnostics.record(context: "学业业务操作", error: error); self.error = error.localizedDescription } }
    }
}
