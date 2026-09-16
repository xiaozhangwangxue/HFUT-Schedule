import SwiftUI

struct OfficialCourseSearchView: View {
    @AppStorage("academicConnectionMode") private var connectionMode = AcademicConnectionMode.direct.rawValue
    @State private var courseName: String
    @State private var code: String
    @State private var results: [OfficialCourseSearchResult] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    init(courseName: String = "", code: String = "") {
        _courseName = State(initialValue: courseName)
        _code = State(initialValue: code.components(separatedBy: "--").first ?? code)
    }

    var body: some View {
        List {
            Section("官方教务开课查询") {
                TextField("课程名称", text: $courseName)
                TextField("课程代码", text: $code)
                    .textInputAutocapitalization(.characters)
                Button("查询其他教学班", systemImage: "magnifyingglass") {
                    Task { await search() }
                }
                .disabled(isLoading || (courseName.trimmed.isEmpty && code.trimmed.isEmpty))
            }
            resultSection
        }
        .navigationTitle("开课查询")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if isLoading { ProgressView("正在查询校方教务…") } }
        .task { if !courseName.trimmed.isEmpty || !code.trimmed.isEmpty { await search() } }
        .refreshable { await search() }
    }

    @ViewBuilder
    private var resultSection: some View {
        if let errorMessage {
            Section { ContentUnavailableView("查询失败", systemImage: "exclamationmark.triangle", description: Text(errorMessage)) }
        } else if !results.isEmpty {
            Section("查询结果（\(results.count)）") {
                ForEach(results) { item in
                    VStack(alignment: .leading, spacing: 5) {
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
                    .padding(.vertical, 4)
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
                semesterID: AcademicPortal.currentSemesterID,
                courseName: courseName.trimmed,
                code: code.trimmed
            )
            if results.isEmpty { errorMessage = "校方接口未查到匹配课程。" }
        } catch {
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

    var body: some View {
        List {
            if let errorMessage {
                ContentUnavailableView("暂时无法读取同班同学", systemImage: "person.2.slash", description: Text(errorMessage))
                Button("登录合工大教务 API", systemImage: "key.fill") { showingLogin = true }
            } else {
                ForEach(classmates) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.nameZh).font(.headline)
                        Text([item.code, item.className, item.gender].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
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
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct OfficialClassroomSearchView: View {
    @State private var selectedDate = Date()
    @State private var campusID = 3
    @State private var buildingID = 0
    @State private var floor = 0
    @State private var buildings: [OfficialBuilding] = []
    @State private var rooms: [OfficialEmptyClassroom] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingLogin = false

    init(query: String = "") {}

    private let campuses = [("屯溪路", 2), ("翡翠湖", 3), ("宣城", 6)]
    private var filteredBuildings: [OfficialBuilding] { buildings.filter { $0.campusAssoc == campusID } }

    var body: some View {
        List {
            Section("按原版列表选择") {
                DatePicker("日期", selection: $selectedDate, displayedComponents: .date)
                Picker("校区", selection: $campusID) {
                    ForEach(campuses, id: \.1) { Text($0.0).tag($0.1) }
                }
                Picker("教学楼", selection: $buildingID) {
                    Text("全部教学楼").tag(0)
                    ForEach(filteredBuildings) { Text($0.nameZh).tag($0.id) }
                }
                Picker("楼层", selection: $floor) {
                    Text("全部楼层").tag(0)
                    ForEach(1...8, id: \.self) { Text("\($0) 层").tag($0) }
                }
                Button("查询空教室", systemImage: "magnifyingglass") { Task { await search() } }
                    .disabled(isLoading)
            }
            if let errorMessage {
                Section {
                    ContentUnavailableView("查询失败", systemImage: "door.left.hand.closed", description: Text(errorMessage))
                    Button("登录合工大教务 API", systemImage: "key.fill") { showingLogin = true }
                }
            } else if !rooms.isEmpty {
                Section("空教室（\(rooms.count)）") {
                    ForEach(rooms) { room in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(room.nameZh).font(.headline)
                            Text(room.campusNameZh)
                            .font(.caption).foregroundStyle(.secondary)
                            if let occupied = room.roomOccupationInfoVms, !occupied.isEmpty {
                                Text(occupied.map { "\($0.startTimeString)-\($0.endTimeString) \($0.activityName)" }.joined(separator: "；"))
                                    .font(.caption2).foregroundStyle(.orange)
                            } else {
                                Text("所选日期暂无占用记录").font(.caption2).foregroundStyle(.green)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("教室状态")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if isLoading { ProgressView("正在查询官方教室数据…") } }
        .task { await prepare() }
        .onChange(of: campusID) { _, _ in buildingID = 0 }
        .refreshable { await search() }
        .sheet(isPresented: $showingLogin) {
            OfficialUniAppLoginView {
                showingLogin = false
                Task { await search() }
            }
        }
    }

    @MainActor
    private func search() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            rooms = try await OfficialCampusAPIClient.shared.fetchEmptyClassrooms(
                date: formatter.string(from: selectedDate),
                campusID: campusID,
                buildingIDs: buildingID == 0 ? [] : [buildingID],
                floors: floor == 0 ? [] : [floor]
            )
            if rooms.isEmpty { errorMessage = "校方接口未查到符合条件的空教室。" }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    private func prepare() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            buildings = try await OfficialCampusAPIClient.shared.fetchBuildings()
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }
}

struct OfficialFailRateView: View {
    @State private var query: String
    @State private var records: [OfficialFailRateRecord] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingLogin = false

    init(courseName: String = "") { _query = State(initialValue: courseName) }

    var body: some View {
        List {
            Section("智慧社区官方接口") {
                TextField("课程名称", text: $query)
                Button("查询挂科率", systemImage: "percent") { Task { await search() } }
                    .disabled(isLoading || query.trimmed.isEmpty)
            }
            if let errorMessage {
                Section {
                    ContentUnavailableView("查询失败", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                    Button("前往安全登录", systemImage: "lock.shield") { showingLogin = true }
                }
            } else {
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
            }
        }
        .navigationTitle("挂科率")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if isLoading { ProgressView("正在读取智慧社区…") } }
        .task { if !query.trimmed.isEmpty { await search() } }
        .refreshable { await search() }
        .sheet(isPresented: $showingLogin, onDismiss: { Task { await search() } }) {
            NavigationStack { LoginPortalView() }
        }
    }

    @MainActor
    private func search() async {
        guard !isLoading, !query.trimmed.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        do {
            records = try await OfficialCampusAPIClient.shared.fetchFailRates(courseName: query.trimmed)
            if records.isEmpty { errorMessage = "智慧社区未返回匹配课程。" }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
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
        NavigationStack {
            Form {
                Section {
                    TextField("学号", text: $username).keyboardType(.numberPad)
                    SecureField("教务系统密码", text: $password)
                } footer: {
                    Text("这是 jwglapp.hfut.edu.cn 官方 API 的独立密码。密码只用于本次登录，应用仅把返回令牌存入系统钥匙串。")
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
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
