import SwiftUI

struct CampusDirectoryItem: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let url: URL?
    var category = ""
}

struct CampusDirectoryClient {
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func offices(keyword: String, page: Int) async throws -> [CampusDirectoryItem] {
        var parts = URLComponents(string: "https://ehall.hfut.edu.cn/api/aggr/aggrlightapp/lightappOrderByInitials")!
        parts.queryItems = [URLQueryItem(name: "code", value: "PC_SH_v2_ANO"), URLQueryItem(name: "returnType", value: "4"),
            URLQueryItem(name: "name", value: keyword), URLQueryItem(name: "current", value: String(page)), URLQueryItem(name: "size", value: "30")]
        let root = try ScheduleSourceParser.object(await data(URLRequest(url: parts.url!)))
        guard let rows = (root["data"] as? [String: Any])?["records"] as? [[String: Any]] else { throw OfficialCampusAPIError.invalidData("办事目录未返回列表") }
        return rows.compactMap { row in
            guard let name = row["name"] as? String else { return nil }
            return CampusDirectoryItem(id: String(describing: row["lightappId"] ?? name), title: name,
                detail: ["serviceDpt", "serviceTime", "processingPlace"].compactMap { row[$0] as? String }.filter { !$0.isEmpty }.joined(separator: " · "),
                url: (row["url"] as? String).flatMap(URL.init(string:)), category: row["serviceDpt"] as? String ?? "")
        }
    }

    static let jobTypes = ["全部", "双选会", "参会单位", "宣讲会", "在线招聘", "职位", "通知公告"]
    func jobs(keyword: String, page: Int, type: Int, xuancheng: Bool) async throws -> [CampusDirectoryItem] {
        var parts = URLComponents(string: "https://dc.bysjy.com.cn/search/provider_new")!
        parts.queryItems = [URLQueryItem(name: "start_page", value: "1"), URLQueryItem(name: "token", value: "yxqqnn1700000" + (xuancheng ? "119" : "002")),
            URLQueryItem(name: "count", value: "30"), URLQueryItem(name: "start", value: String(page))]
        if !keyword.isEmpty { parts.queryItems?.append(URLQueryItem(name: "keyword", value: keyword)) }
        if type > 0 { parts.queryItems?.append(URLQueryItem(name: "type", value: String(type))) }
        let response = try await data(URLRequest(url: parts.url!))
        let text = String(decoding: response, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let json = text.hasPrefix("var __result = ") ? String(text.dropFirst("var __result = ".count)).trimmingCharacters(in: CharacterSet(charactersIn: "; \r\n")) : text
        let root = try ScheduleSourceParser.object(Data(json.utf8))
        guard let rows = root["data"] as? [[String: Any]] else { throw OfficialCampusAPIError.invalidData("就业查询未返回列表") }
        let paths = ["", "jobfair?id=", "company?company_id=", "career?id=", "online?id=", "job?id=", "news?id="]
        return rows.compactMap { row in
            guard let title = row["title"] as? String else { return nil }
            let id = String(describing: row["id"] ?? title), kind = ScheduleSourceParser.integer(row["type"])
            guard paths.indices.contains(kind), kind > 0 else { return nil }
            let category = Self.jobTypes[kind]
            return CampusDirectoryItem(id: "\(kind)|\(id)", title: title, detail: (row["time"] as? String ?? "") + " · " + category,
                url: URL(string: (xuancheng ? "https://xcjy.hfut.edu.cn/" : "https://gdjy.hfut.edu.cn/") + "detail/" + paths[kind] + id), category: category)
        }
    }

    func data(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return data
    }
}

struct CampusDirectoryView: View {
    enum Kind { case offices, jobs }
    let kind: Kind
    @EnvironmentObject private var appState: AppState
    @State private var keyword = ""
    @State private var selectedType = 0
    @State private var selectedDepartment = "全部"
    @State private var rows: [CampusDirectoryItem] = []
    @State private var page = 0
    @State private var hasMore = false
    @State private var busy = false
    @State private var error: String?
    @State private var generation = UUID()
    private let client = CampusDirectoryClient()

    var body: some View {
        List {
            if kind == .jobs {
                Picker("类别", selection: $selectedType) { ForEach(CampusDirectoryClient.jobTypes.indices, id: \.self) { Text(CampusDirectoryClient.jobTypes[$0]).tag($0) } }
            } else if !rows.isEmpty {
                Picker("部门", selection: $selectedDepartment) {
                    Text("全部").tag("全部")
                    ForEach(Array(Set(rows.map(\.category))).filter { !$0.isEmpty }.sorted(), id: \.self) { Text($0).tag($0) }
                }
            }
            ForEach(rows.filter { selectedDepartment == "全部" || $0.category == selectedDepartment }) { item in
                if let url = item.url {
                    AppNavigationLink { PortalWebView(url: url) } label: { row(item) }
                } else { row(item) }
            }
            if busy { ProgressView() }
            if let error { Text(error).foregroundStyle(.red) }
            if hasMore { Button("加载更多") { Task { await load(reset: false) } }.disabled(busy) }
            if !busy, rows.isEmpty, error == nil { ContentUnavailableView("没有匹配内容", systemImage: "magnifyingglass") }
        }
        .navigationTitle(kind == .jobs ? "就业服务" : "办事大厅")
        .searchable(text: $keyword, prompt: "搜索名称或关键词")
        .onSubmit(of: .search) { Task { await load(reset: true) } }
        .task { await load(reset: true) }
        .onChange(of: selectedType) { _, _ in Task { await load(reset: true) } }
        .onChange(of: appState.campus) { _, _ in Task { await load(reset: true) } }
        .refreshable { await load(reset: true) }
    }

    private func row(_ item: CampusDirectoryItem) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(item.title).font(.headline); Text(item.detail).font(.caption).foregroundStyle(.secondary) }
            .padding(.vertical, 4)
    }
    private func load(reset: Bool) async {
        guard !busy || reset else { return }
        let token = UUID(); generation = token; busy = true; error = nil
        let next = reset ? 1 : page + 1
        defer { if generation == token { busy = false } }
        do {
            let fetched = kind == .jobs
                ? try await client.jobs(keyword: keyword, page: next, type: selectedType, xuancheng: appState.campus == .xuancheng)
                : try await client.offices(keyword: keyword, page: next)
            guard generation == token else { return }
            rows = reset ? fetched : rows + fetched
            var ids = Set<String>(); rows = rows.filter { ids.insert($0.id).inserted }
            page = next; hasMore = fetched.count == 30
        } catch { if generation == token { self.error = error.localizedDescription } }
    }
}
