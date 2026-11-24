import SwiftUI

struct CampusNewsHubView: View {
    @State private var categoryQuery = ""
    private func matches(_ title: String) -> Bool { categoryQuery.isEmpty || title.localizedCaseInsensitiveContains(categoryQuery) }
    var body: some View {
        List {
            Section("校园新闻") {
                AppNavigationLink("全校新闻关键词搜索") { PlatformNewsSearchView(keyword: "放假安排") }
                if matches("宣城校区通知公告") {
                    AppNavigationLink("宣城校区通知公告") { CampusNewsCategoryView(category: .xuanchengNotices) }
                }
            }
            Section("合肥教务") {
                ForEach(CampusNewsCategory.hefeiAcademic.filter { matches($0.title) }) { category in
                    AppNavigationLink(category.title) { CampusNewsCategoryView(category: category) }
                }
            }
            Section("宣城教务") {
                ForEach(CampusNewsCategory.xuanchengAcademic.filter { matches($0.title) }) { category in
                    AppNavigationLink(category.title) { CampusNewsCategoryView(category: category) }
                }
            }
            Section("各级学院") {
                AppNavigationLink("院系网站目录") { CampusDepartmentDirectoryView() }
            }
        }.navigationTitle("校园新闻")
            .searchable(text: $categoryQuery, prompt: "筛选教务分类")
    }
}

struct CampusNewsCategoryView: View {
    let category: CampusNewsCategory
    @State private var page = 1
    @State private var totalPages: Int?
    @State private var items: [CampusNewsItem] = []
    @State private var filter = ""
    @State private var loading = false
    @State private var error: String?
    private var filtered: [CampusNewsItem] { filter.isEmpty ? items : items.filter { ($0.title + " " + $0.date).localizedCaseInsensitiveContains(filter) } }
    var body: some View {
        List {
            if let error {
                Section { Text(error).foregroundStyle(.secondary); Button("重试") { Task { await load() } } }
            }
            ForEach(filtered) { item in
                AppNavigationLink(title: item.title) { PortalWebView(url: item.url) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.title).font(.subheadline.weight(.medium))
                        Text(item.date).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if !loading && error == nil && filtered.isEmpty {
                Text(items.isEmpty ? "本页未读取到新闻条目，可打开原网页核实。" : "本页没有匹配的新闻。").foregroundStyle(.secondary).font(.footnote)
            }
            Section {
                HStack {
                    Button("上一页") { page -= 1 }.disabled(loading || page <= 1)
                    Spacer()
                    Text("\(page) / \(totalPages ?? 1)").monospacedDigit().font(.footnote)
                    Spacer()
                    Button("下一页") { page += 1 }.disabled(loading || page >= (totalPages ?? 1))
                }
            }
        }.navigationTitle(category.title)
            .searchable(text: $filter, prompt: "筛选本页标题或日期")
            .task(id: page) { await load() }
            .refreshable { await load() }
            .overlay { if loading { ProgressView("正在读取新闻…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    AppNavigationLink("原网页") { PortalWebView(url: CampusNewsClient.pageURL(category: category, page: page, totalPages: totalPages)) }
                }
            }
    }
    @MainActor private func load() async {
        let requestedPage = page
        loading = true; error = nil
        do {
            let result = try await CampusNewsClient().fetch(category: category, page: requestedPage, totalPages: totalPages)
            guard !Task.isCancelled, page == requestedPage else { return }
            items = result.items; totalPages = result.totalPages; loading = false
        } catch {
            guard !Task.isCancelled, page == requestedPage else { return }
            self.error = error.localizedDescription; loading = false
        }
    }
}

struct CampusDepartmentDirectoryView: View {
    @State private var items: [CampusDepartment] = []
    @State private var query = ""
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.secondary); Button("重新读取") { Task { await load() } } }
            ForEach(items.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { item in
                AppNavigationLink(title: item.name) { PortalWebView(url: item.url) } label: {
                    HStack(spacing: 12) {
                        if let url = item.iconURL {
                            AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: { Image(systemName: "building.columns") }
                                .frame(width: 36, height: 36)
                        }
                        Text(item.name)
                    }
                }
            }
            if items.isEmpty && !loading && error == nil { Text("未读取到院系目录，请打开学校原网页核实。").font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle("各级学院")
            .searchable(text: $query, prompt: "搜索学院")
            .task { await load() }.refreshable { await load() }
            .overlay { if loading { ProgressView("正在读取院系目录…") } }
            .toolbar { AppNavigationLink("学校原网页") { PortalWebView(url: CampusNewsClient.departmentsURL) } }
    }
    @MainActor private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do { items = try await CampusNewsClient().departments() } catch { self.error = error.localizedDescription }
    }
}
