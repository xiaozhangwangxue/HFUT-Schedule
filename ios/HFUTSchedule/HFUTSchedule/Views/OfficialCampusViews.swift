import SwiftUI

struct OfficialCourseSearchView: View {
    @AppStorage("academicConnectionMode") private var connectionMode = AcademicConnectionMode.direct.rawValue
    @State private var courseName: String
    @State private var code: String
    @State private var className = ""
    @State private var semesterID = AcademicPortal.currentSemesterID
    @State private var page = 1
    @State private var results: [OfficialCourseSearchResult] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingLogin = false

    init(courseName: String = "", code: String = "") {
        _courseName = State(initialValue: courseName)
        _code = State(initialValue: code.components(separatedBy: "--").first ?? code)
    }

    var body: some View {
        List {
            Section("官方教务开课查询") {
                Stepper("学期代号 \(semesterID.formatted(.number.grouping(.never)))", value: $semesterID, in: 1...9999)
                TextField("课程名称", text: $courseName)
                TextField("教学班名称", text: $className)
                TextField("课程代码", text: $code)
                    .textInputAutocapitalization(.characters)
                Button("查询其他教学班", systemImage: "magnifyingglass") {
                    Task { await search() }
                }
                .disabled(isLoading || (courseName.trimmed.isEmpty && code.trimmed.isEmpty && className.trimmed.isEmpty))
            }
            resultSection
            if !results.isEmpty {
                AppNavigationLink { AcademicLessonIDsScheduleView(lessonIDs: results.map(\.id)) } label: { Label("查询结果课表", systemImage: "calendar") }
            }
            AcademicPageControls(page: $page, loading: isLoading)
        }
        .navigationTitle("开课查询")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if isLoading { ProgressView("正在查询校方教务…") } }
        .task(id: page) { if !courseName.trimmed.isEmpty || !code.trimmed.isEmpty || !className.trimmed.isEmpty { await search() } }
        .refreshable { await search() }
        .sheet(isPresented: $showingLogin, onDismiss: { Task { await search() } }) {
            AppNavigationStack { LoginPortalView() }
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        if let errorMessage {
            Section {
                ContentUnavailableView("查询失败", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                Button("重新安全登录并同步", systemImage: "lock.shield") { showingLogin = true }
            }
        } else if !results.isEmpty {
            Section("查询结果（\(results.count)）") {
                ForEach(results) { item in
                    AppNavigationLink {
                        CourseDetailView(course: item.detailCourse)
                    } label: { VStack(alignment: .leading, spacing: 5) {
                        Text(item.courseName).font(.headline)
                        Text([item.code, item.className].compactMap { $0 }.joined(separator: " · "))
                            .font(.subheadline).foregroundStyle(.secondary)
                        if !item.teachers.isEmpty {
                            Label(item.teachers.joined(separator: "、"), systemImage: "person")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let schedule = item.schedule {
                            Text(schedule).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4) }
                }
            }
        }
    }

    @MainActor
    private func search() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            let mode = AcademicConnectionMode(rawValue: connectionMode) ?? .direct
            let client = AcademicClient(mode: mode, cookies: HTTPCookieStorage.shared.cookies ?? [])
            results = try await client.searchCourses(
                semesterID: semesterID,
                courseName: courseName.trimmed,
                className: className.trimmed,
                code: code.trimmed,
                page: page
            )
            if results.isEmpty { errorMessage = "校方接口未查到匹配课程。" }
        } catch { AcademicServiceDiagnostics.record(context: "官方教务查询", error: error);
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct OfficialClassmatesView: View {
    let lessonID: Int
    @State private var classmates: [OfficialClassmate] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingLogin = false
    @State private var query = ""
    @State private var selectedGroup = ""
    private var visible: [OfficialClassmate] {
        classmates.filter { (query.isEmpty || "\($0.nameZh) \($0.code) \($0.className)".localizedCaseInsensitiveContains(query)) && (selectedGroup.isEmpty || [$0.className, $0.gender, String($0.code.prefix(4))].contains(selectedGroup)) }
    }
    private var groups: [(String, Int)] {
        let classCounts = Dictionary(grouping: classmates, by: \.className).mapValues(\.count)
        let genderCounts = Dictionary(grouping: classmates, by: \.gender).mapValues(\.count)
        let yearCounts = Dictionary(grouping: classmates, by: { String($0.code.prefix(4)) }).mapValues(\.count)
        return (classCounts.map { ($0.key, $0.value) } + genderCounts.map { ($0.key, $0.value) } + yearCounts.map { ($0.key, $0.value) }).filter { !$0.0.isEmpty }.sorted { $0.0 < $1.0 }
    }

    var body: some View {
        List {
            if let errorMessage {
                ContentUnavailableView("暂时无法读取同班同学", systemImage: "person.2.slash", description: Text(errorMessage))
                if OfficialCampusAPIClient.shared.requiresManualUniAppPassword {
                    Button("输入修改后的教务密码", systemImage: "key.fill") { showingLogin = true }
                } else {
                    Button("使用默认密码自动重试", systemImage: "arrow.clockwise") { Task { await load() } }
                }
            } else {
                Section("统计（\(classmates.count)人）") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            Button("全部") { selectedGroup = "" }.buttonStyle(.bordered)
                            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                                Button("\(group.0) · \(group.1)") { selectedGroup = selectedGroup == group.0 ? "" : group.0 }.buttonStyle(.bordered)
                            }
                        }
                    }
                }
                ForEach(visible) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.nameZh).font(.headline)
                        Text([item.code, item.className, item.gender].filter { !$0.isEmpty }.joined(separator: " · ")).textSelection(.enabled)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "姓名、学号或班级")
        .navigationTitle("同班同学")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if isLoading { ProgressView("正在读取校方名单…") } }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showingLogin) {
            OfficialUniAppLoginView {
                showingLogin = false
                Task { await load() }
            }
        }
    }

    @MainActor
    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            classmates = try await OfficialCampusAPIClient.shared.fetchClassmates(lessonID: lessonID)
            if classmates.isEmpty { errorMessage = "校方接口返回空名单。" }
        } catch { AcademicServiceDiagnostics.record(context: "官方教务查询", error: error);
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct OfficialClassroomSearchView: View {
    @State private var selectedDate = Date()
    @State private var campusID = 3
    @State private var buildingIDs: Set<Int> = []
    @State private var floors: Set<Int> = []
    @State private var buildings: [OfficialBuilding] = []
    @State private var rooms: [OfficialEmptyClassroom] = []
    @State private var namedRooms: [OfficialClassroom] = []
    @State private var query: String
    @State private var searchByName: Bool
    @State private var page = 1
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingLogin = false
    init(query: String = "") { _query = State(initialValue: query); _searchByName = State(initialValue: !query.isEmpty) }
    private let campuses = [("屯溪路", 2), ("翡翠湖", 3), ("宣城", 6)]
    private var filteredBuildings: [OfficialBuilding] { buildings.filter { $0.campusAssoc == campusID } }
    var body: some View {
        List {
            Picker("查询方式", selection: $searchByName) { Text("空教室").tag(false); Text("教室名称").tag(true) }.pickerStyle(.segmented)
            Section("查询条件") {
                if searchByName { TextField("教室名称", text: $query) }
                else {
                    DatePicker("日期", selection: $selectedDate, displayedComponents: .date)
                    Picker("校区", selection: $campusID) { ForEach(campuses, id: \.1) { Text($0.0).tag($0.1) } }
                    AppNavigationLink("教学楼（\(buildingIDs.count == 0 ? "全部" : "已选 \(buildingIDs.count)")）") {
                        List {
                            Button("全部教学楼") { buildingIDs = [] }
                            ForEach(filteredBuildings) { building in
                                Toggle(building.nameZh, isOn: Binding(get: { buildingIDs.contains(building.id) }, set: { if $0 { buildingIDs.insert(building.id) } else { buildingIDs.remove(building.id) } }))
                            }
                        }.navigationTitle("教学楼多选")
                    }
                    AppNavigationLink("楼层（\(floors.count == 0 ? "全部" : "已选 \(floors.count)")）") {
                        List {
                            Button("全部楼层") { floors = [] }
                            ForEach(1...20, id: \.self) { floor in
                                Toggle("\(floor) 层", isOn: Binding(get: { floors.contains(floor) }, set: { if $0 { floors.insert(floor) } else { floors.remove(floor) } }))
                            }
                        }.navigationTitle("楼层多选")
                    }
                }
                Button("查询", systemImage: "magnifyingglass") { page = 1; Task { await search() } }.disabled(isLoading || (searchByName && query.trimmed.isEmpty))
            }
            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                    Button("登录教务") { showingLogin = true }
                }
            }
            if searchByName {
                ForEach(namedRooms) { room in
                    AppNavigationLink { OfficialClassroomScheduleView(roomID: room.id, name: room.nameZh) } label: {
                        VStack(alignment: .leading, spacing: 4) { Text(room.nameZh).font(.headline); Text([room.building?.nameZh, room.floor.map { "\($0)F" }, room.roomType?.nameZh, room.seatsForLesson.map { "\($0) 人" }].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            } else {
                ForEach(rooms) { room in
                    AppNavigationLink { ClassroomDayDetailView(room: room, date: selectedDate) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(room.nameZh).font(.headline)
                            Text(room.campusNameZh).font(.caption).foregroundStyle(.secondary)
                            let occupied = room.roomOccupationInfoVms ?? []
                            Text(occupied.isEmpty ? "全天暂无占用" : "\(occupied.count) 段占用 · 查看空闲时间轴").font(.caption).foregroundStyle(occupied.isEmpty ? .green : .orange)
                        }
                    }
                }
            }
            AcademicPageControls(page: $page, loading: isLoading)
        }
        .navigationTitle("教室状态")
        .overlay { if isLoading { ProgressView("正在查询教室…") } }
        .task { await prepare(); if !query.trimmed.isEmpty { await search() } }
        .onChange(of: page) { _, _ in Task { await search() } }
        .onChange(of: campusID) { _, _ in buildingIDs = [] }
        .onChange(of: searchByName) { _, _ in page = 1; rooms = []; namedRooms = [] }
        .refreshable { await search() }
        .sheet(isPresented: $showingLogin) { OfficialUniAppLoginView { showingLogin = false; Task { await prepare(); await search() } } }
    }
    @MainActor private func search() async {
        guard !isLoading else { return }; isLoading = true; errorMessage = nil; defer { isLoading = false }
        do {
            if searchByName { namedRooms = try await OfficialCampusAPIClient.shared.searchClassrooms(name: query.trimmed, page: page) }
            else {
                let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
                rooms = try await OfficialCampusAPIClient.shared.fetchEmptyClassrooms(date: formatter.string(from: selectedDate), campusID: campusID, buildingIDs: buildingIDs.sorted(), floors: floors.sorted(), page: page)
            }
        } catch { AcademicServiceDiagnostics.record(context: "官方教务查询", error: error); errorMessage = error.localizedDescription }
    }
    @MainActor private func prepare() async {
        do { buildings = try await OfficialCampusAPIClient.shared.fetchBuildings() } catch { AcademicServiceDiagnostics.record(context: "官方教务查询", error: error); errorMessage = error.localizedDescription }
    }
}

struct OfficialFailRateView: View {
    @EnvironmentObject private var scheduleStore: ScheduleStore
    @State private var query: String
    private let lessonCode: String?

    init(courseName: String = "", lessonCode: String? = nil) {
        _query = State(initialValue: courseName)
        self.lessonCode = lessonCode
    }

    var body: some View {
        List {
            #if DEBUG
            if AppUIPreview.enabled { Text("界面预览 · 示例数据").font(.caption).foregroundStyle(.secondary) }
            #endif
            Section("智慧社区官方接口") {
                TextField("课程名称", text: $query)
                AppNavigationLink(title: "挂科率查询结果") {
                    OfficialFailRateResultsView(courseName: query.trimmed, lessonCode: lessonCode)
                } label: { Label("查询挂科率", systemImage: "percent") }
                .disabled(query.trimmed.isEmpty)
            }
            if !ownCourses.isEmpty {
                Section("我的课程 · 点选查询") {
                    ForEach(ownCourses) { course in
                        AppNavigationLink(title: course.name + "挂科率") {
                            OfficialFailRateResultsView(courseName: course.name, lessonCode: course.details?.code)
                        } label: { Text(course.name) }
                    }
                }
            }
        }
        .navigationTitle("挂科率")
        .navigationBarTitleDisplayMode(.inline)
    }
    private var ownCourses: [Course] { OwnCourseLookup.courses(scheduleStore.courses) }
}

/// Results have their own pagination/loading state. Popping this page leaves
/// the query form and its scroll position intact for the next course.
struct OfficialFailRateResultsView: View {
    let courseName: String
    let lessonCode: String?
    @State private var page = 1
    @State private var records: [OfficialFailRateRecord] = []
    @State private var isLoading = false
    @State private var loaded = false
    @State private var errorMessage: String?
    @State private var showingLogin = false
    @State private var requestID = UUID()

    var body: some View {
        List {
            #if DEBUG
            if AppUIPreview.enabled { Text("界面预览 · 示例数据").font(.caption).foregroundStyle(.secondary) }
            #endif
            Section("查询课程") { Text(courseName).font(.headline) }
            if let errorMessage {
                Section {
                    ContentUnavailableView("查询失败", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                    Button("重新查询", systemImage: "arrow.clockwise") { Task { await search() } }
                    Button("前往安全登录", systemImage: "lock.shield") { showingLogin = true }
                }
            } else if loaded && records.isEmpty && !isLoading {
                ContentUnavailableView("暂无匹配课程", systemImage: "magnifyingglass", description: Text("智慧社区未返回本次查询的记录，可返回后换一门课程。"))
            }
            ForEach(records) { record in
                Section("\(record.courseName) · \(record.courseCode)") {
                    ForEach(Array(record.terms.enumerated()), id: \.offset) { _, term in
                        LabeledContent("\(term.year) 第\(term.period)学期") {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(String(format: "挂科率 %.2f%%", (1 - term.successRate) * 100))
                                Text("平均 \(term.averageScore, specifier: "%.1f") · \(term.failCount)/\(term.totalCount) 人")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Section {
                AcademicPageControls(page: $page, loading: isLoading)
            }
        }
        .navigationTitle("挂科率结果")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if isLoading { ProgressView("正在读取智慧社区…") } }
        .task(id: page) { await search() }
        .refreshable { await search() }
        .sheet(isPresented: $showingLogin, onDismiss: { Task { await search() } }) { AppNavigationStack { LoginPortalView() } }
    }

    @MainActor private func search() async {
        guard !courseName.isEmpty else { return }
        let id = UUID(); requestID = id; isLoading = true; errorMessage = nil; records = []
        defer { if requestID == id { isLoading = false; loaded = true } }
        #if DEBUG
        if AppUIPreview.enabled { records = AppUIPreview.failRates(course: courseName); return }
        #endif
        do {
            let fetched = try await OfficialCampusAPIClient.shared.fetchFailRates(courseName: courseName, page: page)
            guard !Task.isCancelled, requestID == id else { return }
            if let lessonCode, !lessonCode.isEmpty {
                let exact = fetched.filter { $0.courseCode == lessonCode }
                records = exact.isEmpty ? fetched : exact
            } else { records = fetched }
        } catch {
            guard !Task.isCancelled, requestID == id else { return }
            AcademicServiceDiagnostics.record(context: "官方挂科率查询", error: error)
            errorMessage = error.localizedDescription
        }
    }
}

struct OfficialUniAppLoginView: View {
    let onSuccess: () -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("academicUsername") private var username = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        AppNavigationStack {
            Form {
                Section {
                    TextField("学号", text: $username).keyboardType(.numberPad)
                    SecureField("教务系统密码", text: $password)
                } footer: {
                    Text("应用已按“ Hfut@#$% + 证件号后六位（末位为 X 时取 X 前六位）”自动尝试 3 次。这里只需输入你后来修改过的教务系统密码；密码不保存，仅保存返回令牌。")
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
                Section {
                    Button(isLoading ? "正在登录…" : "登录官方教务 API") { Task { await login() } }
                        .disabled(isLoading || username.trimmed.isEmpty || password.isEmpty)
                }
            }
            .navigationTitle("合工大教务登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }

    @MainActor
    private func login() async {
        isLoading = true
        errorMessage = nil
        do {
            _ = try await OfficialCampusAPIClient.shared.loginUniApp(username: username, password: password)
            password = ""
            onSuccess()
        } catch { AcademicServiceDiagnostics.record(context: "官方教务查询", error: error);
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct AcademicCourseSelectionView: View {
    @AppStorage("academicConnectionMode") private var connectionMode = AcademicConnectionMode.direct.rawValue
    @State private var turns: [AcademicCourseSelectionTurn] = []
    @State private var manualTurn = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingLogin = false

    var body: some View {
        List {
            if let errorMessage {
                ContentUnavailableView("选课入口读取失败", systemImage: "checklist.unchecked", description: Text(errorMessage))
                Button("重新安全登录", systemImage: "lock.shield") { showingLogin = true }
            }
            if !isLoading && turns.isEmpty && errorMessage == nil {
                Text("校方当前没有开放的选课批次，开放后下拉刷新即可。").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(turns) { turn in
                SourceAnchoredNavigationLink(sourceID: "course-selection-turn-\(turn.id)") {
                    AcademicCourseSelectionDetailView(turnID: turn.id, title: turn.name)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { Text(turn.name).font(.headline); Spacer(); Text("代号 \(turn.id)").font(.caption).foregroundStyle(.secondary) }
                        Text(turn.selectDateTimeText).font(.subheadline).foregroundStyle(.secondary)
                        if !turn.bulletin.trimmed.isEmpty { Text(turn.bulletin).font(.caption).lineLimit(3) }
                        ForEach(turn.addRulesText, id: \.self) { Text($0).font(.caption2).foregroundStyle(.secondary) }
                    }
                    .padding(.vertical, 4)
                }
            }
            Section("隐藏入口") {
                Text("一些不符合自身条件的入口不会显示，可像原版一样输入右上角代号查看。")
                    .font(.footnote).foregroundStyle(.secondary)
                TextField("输入数字代号", text: $manualTurn).keyboardType(.numberPad)
                if let turnID = Int(manualTurn) {
                    AppNavigationLink("查看入口 \(turnID)") {
                        AcademicCourseSelectionDetailView(turnID: turnID, title: "入口 \(turnID)")
                    }
                }
            }
        }
        .navigationTitle("选课")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if isLoading { ProgressView("正在读取选课入口…") } }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showingLogin, onDismiss: { Task { await load() } }) {
            AppNavigationStack { LoginPortalView() }
        }
    }

    @MainActor private func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            let mode = AcademicConnectionMode(rawValue: connectionMode) ?? .direct
            turns = try await AcademicClient(mode: mode, cookies: CampusSessionStore.shared.allCookies)
                .fetchCourseSelectionTurns()
        } catch { AcademicServiceDiagnostics.record(context: "官方教务查询", error: error); errorMessage = error.localizedDescription }
        isLoading = false
    }
}

private struct AcademicCourseSelectionDetailView: View {
    let turnID: Int
    let title: String
    @AppStorage("academicConnectionMode") private var connectionMode = AcademicConnectionMode.direct.rawValue
    @State private var lessons: [AcademicSelectableLesson] = []
    @State private var studentCounts: [Int: Int] = [:]
    @State private var query = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingSelected = false
    @State private var selectedIDs: Set<Int> = []
    @State private var pendingLesson: AcademicSelectableLesson?
    @State private var operationMessage: String?
    @State private var submitting = false

    private var mode: AcademicConnectionMode { AcademicConnectionMode(rawValue: connectionMode) ?? .direct }
    private var visibleLessons: [AcademicSelectableLesson] {
        query.trimmed.isEmpty ? lessons : lessons.filter { "\($0.courseName) \($0.code) \($0.teachers.joined())".localizedCaseInsensitiveContains(query.trimmed) }
    }

    var body: some View {
        List {
            Picker("课程范围", selection: $showingSelected) { Text("可选课程").tag(false); Text("已选课程").tag(true) }.pickerStyle(.segmented)
            if let operationMessage { Text(operationMessage).foregroundStyle(.secondary) }
            if let errorMessage { ContentUnavailableView("课程读取失败", systemImage: "exclamationmark.triangle", description: Text(errorMessage)) }
            ForEach(visibleLessons) { lesson in
                VStack(alignment: .leading, spacing: 5) {
                    Text(lesson.courseName).font(.headline)
                    Text(lesson.code).font(.caption).foregroundStyle(.secondary)
                    if lesson.limitCount > 0 {
                        let enrolled = studentCounts[lesson.id] ?? 0
                        let ratio = min(1, Double(enrolled) / Double(lesson.limitCount))
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text("已选 \(enrolled) / \(lesson.limitCount)")
                                    .font(.caption)
                                    .foregroundStyle(ratio >= 1 ? .red : .secondary)
                                Spacer()
                                Text("\(Int(ratio * 100))%")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            ProgressView(value: ratio)
                                .tint(ratio >= 1 ? .red : AppTheme.accent)
                        }
                    } else {
                        Text("限选人数待公布").font(.caption).foregroundStyle(.secondary)
                    }
                    if !lesson.teachers.isEmpty { Text(lesson.teachers.joined(separator: "、")).font(.caption) }
                    if let schedule = lesson.schedule { Text(schedule).font(.caption2).foregroundStyle(.secondary) }
                    if let remark = lesson.remark, !remark.isEmpty { Text(remark).font(.caption2) }
                    HStack {
                        AppNavigationLink("与已选课程对照") { AcademicSelectionScheduleView(turnID: turnID, candidateID: lesson.id) }.font(.caption)
                        Spacer()
                        Button(selectedIDs.contains(lesson.id) ? "退课" : "选课", role: selectedIDs.contains(lesson.id) ? .destructive : nil) { pendingLesson = lesson }
                            .buttonStyle(.bordered).disabled(submitting)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle(title)
        .searchable(text: $query, prompt: "课程、代码、教师")
        .toolbar {
            AppNavigationLink("冲突预览") {
                PortalWebView(url: AcademicPortal.url("for-std/course-table", mode: mode), academicMode: mode)
            }
            AppNavigationLink("已选课程周课表") {
                AcademicSelectionScheduleView(turnID: turnID)
            }
        }
        .overlay { if isLoading { ProgressView("正在读取可选课程…") } }
        .task(id: showingSelected) { await load() }
        .confirmationDialog(pendingLesson.map { "确认\(selectedIDs.contains($0.id) ? "退选" : "选择")《\($0.courseName)》？" } ?? "确认操作", isPresented: Binding(get: { pendingLesson != nil }, set: { if !$0 { pendingLesson = nil } }), titleVisibility: .visible) {
            Button("确认提交", role: pendingLesson.map { selectedIDs.contains($0.id) } == true ? .destructive : nil) {
                if let lesson = pendingLesson { Task { await submit(lesson) } }
            }
        }
        .refreshable { await load() }
    }

    @MainActor private func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            let client = AcademicClient(mode: mode, cookies: CampusSessionStore.shared.allCookies)
            let selected = try await client.fetchSelectedLessons(turnID: turnID)
            selectedIDs = Set(selected.map(\.id))
            lessons = showingSelected ? selected : try await client.fetchSelectableLessons(turnID: turnID)
            await loadStudentCounts()
        } catch { AcademicServiceDiagnostics.record(context: "官方教务查询", error: error); errorMessage = error.localizedDescription }
        isLoading = false
    }

    @MainActor private func submit(_ lesson: AcademicSelectableLesson) async {
        let dropping = selectedIDs.contains(lesson.id)
        pendingLesson = nil; submitting = true; defer { submitting = false }
        do {
            let result = try await AcademicClient(mode: mode, cookies: CampusSessionStore.shared.allCookies).submitCourseSelection(turnID: turnID, lessonID: lesson.id, dropping: dropping)
            operationMessage = result.message
            if result.success { await load() }
        } catch { AcademicServiceDiagnostics.record(context: "官方教务查询", error: error); operationMessage = error.localizedDescription }
    }

    @MainActor
    private func loadStudentCounts() async {
        let ids = lessons.map(\.id)
        guard !ids.isEmpty else { return }
        studentCounts = (try? await AcademicClient(mode: mode, cookies: CampusSessionStore.shared.allCookies)
            .fetchLessonStudentCounts(lessonIDs: ids)) ?? [:]
    }
}

struct AcademicTeachingSurveyView: View {
    @AppStorage("academicConnectionMode") private var connectionMode = AcademicConnectionMode.direct.rawValue
    @State private var lessons: [AcademicSurveyLesson] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingLogin = false

    private var mode: AcademicConnectionMode { AcademicConnectionMode(rawValue: connectionMode) ?? .direct }

    var body: some View {
        List {
            if let errorMessage {
                ContentUnavailableView("评教列表读取失败", systemImage: "text.bubble", description: Text(errorMessage))
                Button("重新安全登录", systemImage: "lock.shield") { showingLogin = true }
            }
            ForEach(lessons) { lesson in
                Section {
                    ForEach(lesson.teachers) { teacher in
                        if teacher.submitted {
                            Label("\(teacher.name) · 已评", systemImage: "checkmark.circle.fill").foregroundStyle(.secondary)
                        } else {
                            SourceAnchoredNavigationLink(sourceID: "survey-teacher-\(teacher.id)") {
                                AcademicSurveyFormView(taskID: teacher.id, teacher: teacher.name)
                            } label: {
                                Label(teacher.name, systemImage: "person.crop.circle.badge.questionmark")
                            }
                        }
                    }
                } header: {
                    VStack(alignment: .leading) {
                        Text(lesson.courseName)
                        Text([lesson.code, lesson.department, lesson.deadline].compactMap { $0 }.joined(separator: " · "))
                    }
                }
            }
        }
        .navigationTitle("教师评教")
        .toolbar {
            AppNavigationLink("全部教师评教") { AcademicBulkSurveyView(lessons: lessons) }
                .disabled(isLoading || lessons.flatMap(\.teachers).allSatisfy(\.submitted))
        }
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if isLoading { ProgressView("正在读取评教状态…") } }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showingLogin, onDismiss: { Task { await load() } }) {
            AppNavigationStack { LoginPortalView() }
        }
    }

    @MainActor private func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            lessons = try await AcademicClient(mode: mode, cookies: CampusSessionStore.shared.allCookies)
                .fetchTeachingSurveys(semesterID: AcademicPortal.currentSemesterID)
        } catch { AcademicServiceDiagnostics.record(context: "官方教务查询", error: error); errorMessage = error.localizedDescription }
        isLoading = false
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
