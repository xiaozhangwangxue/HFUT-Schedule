import SwiftUI

struct CloudCommunityView: View {
    @StateObject private var client = CloudCommunityClient.shared
    @EnvironmentObject private var eventsStore: CustomEventStore
    @EnvironmentObject private var studentStore: AcademicStudentStore
    @AppStorage("cloudCommunityFilterMatches") private var filterMatches = false
    @AppStorage("cloudCommunityIncludeExpired") private var includeExpired = false
    @AppStorage("cloudCommunitySort") private var sort = "timeline"
    @AppStorage("cloudCommunityReverse") private var reverse = false
    @AppStorage("selectedCampus") private var selectedCampus = "合肥校区"
    @State private var tab = 0
    @State private var query = ""
    @State private var message: String?
    @State private var contributing: CloudCommunityEvent?
    @State private var deleting: CloudCommunityEvent?
    @State private var editingLocal: CustomEvent?
    private var campus: String {
        let known = studentStore.info?.campus ?? ""
        return (known.isEmpty ? selectedCampus : known).contains("宣城") ? "XUANCHENG" : "HEFEI"
    }
    private var listLoading: Bool { tab == 2 ? client.myLoading : client.loading }
    private var filtered: [CloudCommunityEvent] {
        var list = tab == 2 ? client.myEvents : client.events
        if tab == 0 && filterMatches { list = list.filter { $0.applies(to: studentStore.info?.className ?? "", campus: campus) } }
        if !query.isEmpty { list = list.filter { [$0.name, $0.description ?? "", $0.timeDescription, $0.applicableClasses, $0.contributorClass ?? ""].joined(separator: " ").localizedCaseInsensitiveContains(query) } }
        list.sort {
            let lhs = sort == "created" ? $0.created ?? .distantPast : $0.relevantDate
            let rhs = sort == "created" ? $1.created ?? .distantPast : $1.relevantDate
            return lhs == rhs ? $0.id < $1.id : lhs < rhs
        }
        return reverse ? list.reversed() : list
    }
    private var localEvents: [CustomEvent] {
        eventsStore.events.filter { $0.groupID?.hasPrefix("supabase:") == true }
            .filter { query.isEmpty || ($0.title + " " + $0.detail).localizedCaseInsensitiveContains(query) }.sorted { $0.start < $1.start }
    }
    var body: some View {
        List {
            Section {
                Picker("栏目", selection: $tab) { Text("发现").tag(0); Text("已下载").tag(1); Text("我的贡献").tag(2) }.pickerStyle(.segmented)
                AppNavigationLink { CloudCommunityAccountView(client: client) } label: {
                    Label(client.hasSession ? client.accountEmail : "登录 / 注册云共建账号", systemImage: "person.crop.circle")
                }
            }
            if tab == 0 { filterSection }
            if tab == 1 { downloadedSection }
            else {
                if tab == 2 && !client.hasSession {
                    Text("登录后查看和管理自己贡献的日程。").foregroundStyle(.secondary)
                }
                if listLoading { HStack { ProgressView(); Text("正在获取日程…") } }
                ForEach(filtered) { item in
                    AppNavigationLink { CloudCommunityEventView(event: item, client: client) } label: { cloudRow(item) }
                        .swipeActions {
                            if tab == 2 {
                                Button("删除", role: .destructive) { deleting = item }
                                Button("编辑") { contributing = item }.tint(.blue)
                            }
                        }
                }
                if filtered.isEmpty && !listLoading { Text("没有符合条件的云日程。").font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("云共建")
        .searchable(text: $query, prompt: "搜索名称、说明或适用班级")
        .refreshable { await refresh() }
        .task(id: tab) { await refresh() }
        .onChange(of: includeExpired) { _, _ in Task { await refresh() } }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("贡献日程", systemImage: "plus") { contributing = newEvent() }.disabled(!client.hasSession)
            }
        }
        .sheet(item: $contributing, onDismiss: { Task { await refresh() } }) { event in
            AppNavigationStack { CloudCommunityContributionView(event: event, client: client, contributorClass: (studentStore.info?.className ?? "") + (campus == "XUANCHENG" ? "(宣)" : "(肥)")) }
        }
        .sheet(item: $editingLocal) { CustomEventEditor(event: $0) }
        .confirmationDialog("删除这条云端贡献？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("删除云端日程", role: .destructive) {
                guard let item = deleting else { return }; deleting = nil
                Task { do { try await client.delete(item) } catch { message = error.localizedDescription } }
            }
        }
        .alert("云共建", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("好") { message = nil }
        } message: { Text(message ?? "") }
    }
    private var filterSection: some View {
        Section {
            Toggle("仅显示适合我的校区与班级", isOn: $filterMatches)
            Toggle("包含已结束日程", isOn: $includeExpired)
            Picker("排序", selection: $sort) { Text("日程时间").tag("timeline"); Text("上传时间").tag("created") }
            Toggle("倒序排列", isOn: $reverse)
        } footer: { if filterMatches && studentStore.info?.className.isEmpty != false { Text("未获取班级时只显示通用班级日程，可先完成教务登录。") } }
    }
    @ViewBuilder private var downloadedSection: some View {
        Section("已下载到本地") {
            ForEach(localEvents) { item in
                Button { editingLocal = item } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.title).foregroundStyle(.primary)
                        Text(item.end.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        if let id = item.groupID.flatMap({ Int($0.replacingOccurrences(of: "supabase:", with: "")) }),
                           let latest = client.events.first(where: { $0.id == id }), client.importedVersions[id] != latest {
                            Text("云端有更新，可在发现页覆盖本地版本").font(.caption).foregroundStyle(.orange)
                        }
                    }
                }.swipeActions {
                    Button("移除本地", role: .destructive) {
                        if !eventsStore.remove(item.id) { message = eventsStore.storageError ?? "本地日程删除失败" }
                    }
                }
            }
            if localEvents.isEmpty { Text("还没有下载云日程。").foregroundStyle(.secondary) }
        }
    }
    private func cloudRow(_ item: CloudCommunityEvent) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(item.name).font(.headline)
            Text(item.timeDescription).font(.caption).foregroundStyle(.secondary)
            Text(item.relevantDate.formatted(date: .abbreviated, time: .shortened)).font(.caption)
            if eventsStore.events.contains(where: { $0.groupID == item.localGroupID }) {
                Text(client.importedVersions[item.id] == item ? "已下载" : "云端有更新").font(.caption).foregroundStyle(AppTheme.accent)
            }
        }
    }
    @MainActor private func refresh() async {
        do {
            if tab == 2 { if client.hasSession { try await client.loadMyEvents() } }
            else { try await client.loadEvents(includeExpired: includeExpired) }
        } catch { message = error.localizedDescription }
    }
    private func newEvent() -> CloudCommunityEvent {
        .init(id: -1, name: "", description: nil, timeDescription: "", startTime: CloudCommunityDate.string(Date()),
            endTime: CloudCommunityDate.string(Date().addingTimeInterval(3600)), contributorEmail: nil, contributorClass: nil,
            applicableClasses: studentStore.info?.className ?? "EMPTY", createdTime: nil, url: nil, campus: campus, type: "SCHEDULE")
    }
}

struct CloudCommunityEventView: View {
    let event: CloudCommunityEvent
    @ObservedObject var client: CloudCommunityClient
    @EnvironmentObject private var store: CustomEventStore
    @State private var importing = false
    @State private var message: String?
    private var existing: CustomEvent? { store.events.first { $0.groupID == event.localGroupID } }
    var body: some View {
        Form {
            Section {
                Text(event.name).font(.title3.bold())
                if let description = event.description, description != "NULL" { Text(description).textSelection(.enabled) }
                LabeledContent("类型", value: event.type == "NET_COURSE" ? "截止事项" : "日程")
                if let start = event.start { LabeledContent("开始", value: start.formatted(date: .abbreviated, time: .shortened)) }
                if let end = event.end { LabeledContent("结束", value: end.formatted(date: .abbreviated, time: .shortened)) }
                if !event.timeDescription.isEmpty { Text(event.timeDescription) }
                if let url = event.safeURL { AppNavigationLink("打开相关网页") { PortalWebView(url: url) } }
            }
            Section("适用范围") {
                LabeledContent("校区", value: event.campus == "DEFAULT" ? "通用" : event.campus == "XUANCHENG" ? "宣城" : "合肥")
                Text(event.applicableClasses.isEmpty || event.applicableClasses == "EMPTY" ? "所有班级" : event.applicableClasses)
                if let value = event.contributorClass { LabeledContent("贡献班级", value: value) }
                if let email = event.contributorEmail { LabeledContent("贡献者", value: "********" + String(email.prefix { $0 != "@" }.suffix(2))) }
                if let created = event.created { LabeledContent("上传时间", value: created.formatted(date: .abbreviated, time: .shortened)) }
                if let count = client.forkCounts[event.id] { LabeledContent("下载次数", value: String(count)) }
            }
            Section {
                if let local = event.localEvent(existingID: ScheduleSourceParser.stableID("cloud-calendar|\(event.id)")) {
                    SingleCalendarExportButton(occurrence: PlatformScheduleOccurrence(id: "cloud|\(event.id)",
                        sourceID: local.id.uuidString, kind: local.kind == .deadline ? .deadline : .event,
                        title: local.title, location: local.location, detail: local.detail,
                        start: local.start, end: max(local.end, local.start.addingTimeInterval(60))))
                }
                Button {
                    Task {
                        importing = true; defer { importing = false }
                        do { let updated = try await client.importEvent(event, into: store); message = updated ? "已覆盖本地日程" : "已克隆到本地日程" }
                        catch { message = error.localizedDescription }
                    }
                } label: { HStack { Text(existing == nil ? "克隆到本地日程" : "覆盖本地日程"); if importing { ProgressView() } } }.disabled(importing)
            } footer: { Text("下载后可在聚焦、课表与自建日程中查看；覆盖会保留本地记录ID。") }
        }.navigationTitle("云日程")
            .task { await client.loadForkCount(event.id) }
            .alert("云共建", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("好") { message = nil } } message: { Text(message ?? "") }
    }
}

struct CloudCommunityAccountView: View {
    @ObservedObject var client: CloudCommunityClient
    @EnvironmentObject private var studentStore: AcademicStudentStore
    @State private var account = ""
    @State private var password = ""
    @State private var busy = false
    @State private var message: String?
    var body: some View {
        Form {
            if client.hasSession {
                Section {
                    LabeledContent("云共建账号", value: client.accountEmail)
                    Button("验证并刷新登录") { run { try await client.verifySession(); message = "登录状态有效" } }
                    Button("退出云共建账号", role: .destructive) { client.signOut() }
                }
            } else {
                Section {
                    TextField("学号或学校邮箱", text: $account).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.emailAddress)
                    SecureField("云共建密码", text: $password)
                    Button("登录") { run { try await client.signIn(account: account, password: password); password = ""; message = "登录成功" } }.disabled(password.isEmpty || busy)
                    Button("注册") {
                        run {
                            let loggedIn = try await client.signUp(account: account, password: password)
                            password = ""; message = loggedIn ? "注册成功" : "注册请求已完成，请到学校邮箱查收激活邮件，再回来登录。"
                        }
                    }.disabled(password.count < 6 || busy)
                } footer: { Text("使用学校邮箱注册云共建账号。密码与统一身份认证独立；会话保存在钥匙串中。") }
            }
            if busy { ProgressView("正在连接云共建…") }
            AppNavigationLink("打开学校邮箱") { CampusMailPageView() }
        }.navigationTitle("云共建账号")
            .onAppear { if account.isEmpty { account = studentStore.info?.studentID ?? "" } }
            .alert("云共建账号", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("好") { message = nil } } message: { Text(message ?? "") }
    }
    private func run(_ operation: @escaping () async throws -> Void) {
        guard !busy else { return }; busy = true
        Task { defer { busy = false }; do { try await operation() } catch { message = error.localizedDescription } }
    }
}

struct CloudCommunityContributionView: View {
    @State var event: CloudCommunityEvent
    @ObservedObject var client: CloudCommunityClient
    let contributorClass: String
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var message: String?
    private var start: Binding<Date> { Binding(get: { event.start ?? Date() }, set: { event.startTime = CloudCommunityDate.string($0) }) }
    private var end: Binding<Date> { Binding(get: { event.end ?? Date() }, set: { event.endTime = CloudCommunityDate.string($0) }) }
    var body: some View {
        Form {
            Section("日程") {
                TextField("名称", text: $event.name)
                Picker("类型", selection: $event.type) { Text("日程").tag("SCHEDULE"); Text("截止事项").tag("NET_COURSE") }
                TextField("时间、地点说明", text: $event.timeDescription)
                TextField("详细说明", text: Binding(get: { event.description ?? "" }, set: { event.description = $0 }), axis: .vertical)
                DatePicker("开始", selection: start)
                DatePicker("结束", selection: end, in: (event.start ?? .distantPast)...)
                TextField("相关网址（可选）", text: Binding(get: { event.url ?? "" }, set: { event.url = $0.isEmpty ? nil : $0 })).textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            Section("适用范围") {
                Picker("校区", selection: $event.campus) { Text("通用").tag("DEFAULT"); Text("合肥").tag("HEFEI"); Text("宣城").tag("XUANCHENG") }
                TextField("适用班级，逗号分隔；EMPTY表示全部", text: $event.applicableClasses)
                Text("贡献者：\(client.accountEmail)\n班级：\(contributorClass)").font(.caption).foregroundStyle(.secondary)
            }
            Section { Text("提交后日程及适用范围会公开，贡献账号与班级将随日程记录上传。").font(.footnote) }
            if busy { ProgressView("正在提交…") }
        }.navigationTitle(event.id > 0 ? "编辑云端贡献" : "贡献日程")
            .onChange(of: event.startTime) { _, _ in
                if let start = event.start, let end = event.end, end < start { event.endTime = event.startTime }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("提交") {
                        busy = true
                        Task { defer { busy = false }; do { try await client.contribute(event, className: contributorClass, update: event.id > 0); dismiss() } catch { message = error.localizedDescription } }
                    }.disabled(!event.isValid || busy || (!event.url.orEmpty.isEmpty && event.safeURL == nil))
                }
            }
            .alert("提交未完成", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("好") { message = nil } } message: { Text(message ?? "") }
    }
}
private extension Optional where Wrapped == String { var orEmpty: String { self ?? "" } }
