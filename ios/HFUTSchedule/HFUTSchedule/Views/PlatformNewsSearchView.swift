import SwiftUI

enum PlatformNewsSearchClient {
    static func request(keyword: String, page: Int) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://news.hfut.edu.cn/zq_search.jsp?wbtreeid=1137")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let value = Data(keyword.utf8).base64EncodedString()
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        request.httpBody = "sitenewskeycode=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")&currentnum=\(max(1, page))".data(using: .utf8)
        return request
    }
    static func parse(_ html: String) -> [PublicExamNotice] {
        let base = URL(string: "https://news.hfut.edu.cn/")!
        var seen = Set<String>()
        return AcademicHTMLText.matches(html, "<li\\b[^>]*>(.*?)</li>").compactMap { row in
            guard let anchor = AcademicHTMLText.matches(row[1], "<a\\b([^>]*)>(.*?)</a>").first,
                  let url = URL(string: AcademicHTMLText.attribute(anchor[1], "href"), relativeTo: base)?.absoluteURL,
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  let host = url.host?.lowercased(), host == "hfut.edu.cn" || host.hasSuffix(".hfut.edu.cn"),
                  seen.insert(url.absoluteString).inserted else { return nil }
            let titleAttribute = AcademicHTMLText.attribute(anchor[1], "title")
            let title = AcademicHTMLText.clean(titleAttribute.isEmpty ? anchor[2] : titleAttribute)
            guard !title.isEmpty else { return nil }
            let date = AcademicHTMLText.matches(row[1], "\\d{4}[-/.]\\d{1,2}[-/.]\\d{1,2}").first?[0] ?? ""
            return PublicExamNotice(title: title, date: date, url: url)
        }
    }
    static func fetch(keyword: String, page: Int) async throws -> [PublicExamNotice] {
        let (data, response) = try await URLSession.shared.data(for: request(keyword: keyword, page: page))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8) else { throw AcademicClientError.invalidData("新闻搜索读取失败") }
        return parse(html)
    }
}

struct PlatformNewsSearchView: View {
    @State private var keyword: String
    @State private var submitted: String
    @State private var page = 1
    @State private var items: [PublicExamNotice] = []
    @State private var loading = false
    @State private var error: String?
    init(keyword: String = "") { _keyword = State(initialValue: keyword); _submitted = State(initialValue: keyword) }
    var body: some View {
        List {
            Section("校园新闻搜索") {
                TextField("关键词", text: $keyword).onSubmit { search() }
                Button("搜索", systemImage: "magnifyingglass") { search() }.disabled(keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(items) { item in
                AppNavigationLink { PortalWebView(url: item.url).navigationTitle(item.title) } label: {
                    VStack(alignment: .leading, spacing: 4) { Text(item.title); Text(item.date).font(.caption).foregroundStyle(.secondary) }
                }
            }
            if !submitted.isEmpty {
                HStack {
                    Button("上一页") { page -= 1 }.disabled(page == 1 || loading)
                    Spacer(); Text("第 \(page) 页"); Spacer()
                    Button("下一页") { page += 1 }.disabled(loading || items.isEmpty)
                }
                if !loading && error == nil && items.isEmpty { Text("本页未读取到匹配新闻。可修改关键词或稍后重试。") }
            }
        }.navigationTitle("校园新闻")
            .task(id: "\(submitted)|\(page)") { await load() }
            .refreshable { await load() }
            .overlay { if loading { ProgressView("正在读取新闻…") } }
    }
    private func search() { submitted = keyword.trimmingCharacters(in: .whitespacesAndNewlines); page = 1 }
    @MainActor private func load() async {
        guard !submitted.isEmpty else { return }
        let query = submitted, requestedPage = page
        loading = true; error = nil
        do {
            let result = try await PlatformNewsSearchClient.fetch(keyword: query, page: requestedPage)
            guard !Task.isCancelled, submitted == query, page == requestedPage else { return }
            items = result; loading = false
        } catch {
            guard !Task.isCancelled, submitted == query, page == requestedPage else { return }
            self.error = error.localizedDescription; loading = false
        }
    }
}
