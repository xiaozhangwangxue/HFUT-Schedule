import SwiftUI

struct CampusProposal: Decodable, Identifiable {
    struct Tag: Decodable, Identifiable { let id: Int64; let name: String }
    let id: Int64
    let title: String
    let state: String
    let body: String?
    let labels: [Tag]
    let html_url: URL
    var stage: String {
        let ids = Set(labels.map(\.id))
        let stages: [(Int64, String)] = [(10356457015,"已发布"),(10356445150,"测试"),(10356443852,"开发"),(10544808661,"设计"),(6088920400,"暂不采纳"),(10335171318,"纳入计划")]
        return stages.first { ids.contains($0.0) }?.1 ?? (state == "open" ? "待评估" : "已关闭")
    }
}

struct CampusProposalView: View {
    @State private var proposals: [CampusProposal] = []
    @State private var keyword = ""
    @State private var selectedStage = "全部"
    @State private var page = 0
    @State private var busy = false
    @State private var more = false
    @State private var error: String?
    private let stages = ["全部", "待评估", "纳入计划", "设计", "开发", "测试", "已发布", "暂不采纳", "已关闭"]
    var body: some View {
        List {
            Picker("状态", selection: $selectedStage) { ForEach(stages, id: \.self) { Text($0).tag($0) } }
            ForEach(proposals.filter { (selectedStage == "全部" || $0.stage == selectedStage) && (keyword.isEmpty || $0.title.localizedCaseInsensitiveContains(keyword)) }) { proposal in
                DisclosureGroup {
                    Text(proposal.body ?? "暂无说明").font(.subheadline).textSelection(.enabled)
                    HStack { ForEach(proposal.labels) { Text($0.name).font(.caption2).padding(4).background(.quaternary, in: Capsule()) } }
                    AppNavigationLink("查看原提案和讨论") { PortalWebView(url: proposal.html_url) }
                } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(proposal.title).font(.headline)
                        Label(proposal.stage, systemImage: proposal.state == "open" ? "circle.dotted" : "checkmark.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if busy { ProgressView() }
            if let error { Text(error).foregroundStyle(.red) }
            if more { Button("加载更多") { Task { await load(reset: false) } }.disabled(busy) }
        }.navigationTitle("事务跟踪").searchable(text: $keyword)
            .task { await load(reset: true) }.refreshable { await load(reset: true) }
    }
    private func load(reset: Bool) async {
        guard !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            let next = reset ? 1 : page + 1
            let url = URL(string: "https://api.github.com/repos/Chiu-xaH/HFUT-Schedule/issues?sort=created&state=all&page=\(next)&per_page=30")!
            var request = URLRequest(url: url); request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let data = try await CampusDirectoryClient().data(request)
            let rows = try JSONDecoder().decode([CampusProposal].self, from: data)
            proposals = reset ? rows : proposals + rows; page = next; more = rows.count == 30
        } catch { self.error = error.localizedDescription }
    }
}
