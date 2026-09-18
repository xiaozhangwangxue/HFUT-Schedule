import SwiftUI

/// 对应 Android 版 school/student/TodayCampus.kt：
/// 顶部「检索功能」输入框 + 内置 stu.json 目录分区 + 智慧社区补充应用。
struct TodayCampusView: View {
    @Environment(\.openURL) private var openURL

    @State private var query = ""
    @State private var localSections: [TodayCampusLocalSection] = []
    @State private var communityApps: [OfficialTodayCampusApp] = []
    @State private var isLoadingCommunity = false
    @State private var errorMessage: String?

    private let studentPortalURL = URL(string: "https://stu.hfut.edu.cn/")!
    private let grid = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]

    var body: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

            ScrollView {
                if normalizedQuery.isEmpty {
                    catalogContent
                } else {
                    searchContent
                }
            }
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("今日校园")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    openTodayCampusApp()
                } label: {
                    Image(systemName: "app.badge")
                }
                .accessibilityLabel("打开今日校园 App")

                Button("学工系统") {
                    openURL(studentPortalURL)
                }
            }
        }
        .task {
            loadBundledApps()
            await loadCommunityApps()
        }
        .refreshable { await loadCommunityApps() }
    }

    // MARK: - 顶部检索框（对应原版 CustomTextField「检索功能」）

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("检索功能", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !normalizedQuery.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .adaptiveGlass(cornerRadius: 14, tint: AppTheme.accent.opacity(0.05))
    }

    // MARK: - 目录内容

    @ViewBuilder
    private var catalogContent: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            ForEach(localSections) { section in
                if !section.apps.isEmpty {
                    appSection(title: section.categoryName, apps: section.apps.map(TodayCampusDisplayApp.init))
                }
            }

            if !communityApps.isEmpty || isLoadingCommunity || errorMessage != nil {
                communitySection
            } else if localSections.isEmpty {
                ContentUnavailableView(
                    "今日校园目录读取失败",
                    systemImage: "square.grid.2x2",
                    description: Text(errorMessage ?? "内置目录 stu.json 未随应用打包。")
                )
                .frame(maxWidth: .infinity, minHeight: 260)
            }
        }
        .padding(.horizontal, 11)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var searchContent: some View {
        if filteredApps.isEmpty {
            ContentUnavailableView.search(text: query)
                .frame(maxWidth: .infinity, minHeight: 300)
        } else {
            LazyVStack(alignment: .leading, spacing: 12) {
                appSection(title: "检索结果（\(filteredApps.count)）", apps: filteredApps)
            }
            .padding(.horizontal, 11)
            .padding(.bottom, 16)
        }
    }

    @ViewBuilder
    private var communitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("智慧社区")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            if isLoadingCommunity && communityApps.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("正在加载智慧社区应用…").font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else if communityApps.isEmpty, let errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(errorMessage).font(.footnote).foregroundStyle(.secondary)
                    Button("重新加载", systemImage: "arrow.clockwise") {
                        Task { await loadCommunityApps() }
                    }
                    .font(.footnote)
                }
                .padding(.vertical, 4)
            } else {
                appGrid(apps: communityApps.map(TodayCampusDisplayApp.init))
            }
        }
    }

    @ViewBuilder
    private func appSection(title: String, apps: [TodayCampusDisplayApp]) -> some View {
        if !apps.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                appGrid(apps: apps)
            }
        }
    }

    private func appGrid(apps: [TodayCampusDisplayApp]) -> some View {
        LazyVGrid(columns: grid, spacing: 6) {
            ForEach(apps) { app in
                SourceAnchoredNavigationLink(sourceID: "today-campus-\(app.id)") {
                    PortalWebView(url: app.url)
                } label: {
                    TodayCampusAppCard(app: app)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 数据

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredApps: [TodayCampusDisplayApp] {
        let local = localSections.flatMap(\.apps).map(TodayCampusDisplayApp.init)
        let remote = communityApps.map(TodayCampusDisplayApp.init)
        return (local + remote).filter { $0.name.localizedCaseInsensitiveContains(normalizedQuery) }
    }

    private func loadBundledApps() {
        guard localSections.isEmpty else { return }
        guard let url = Bundle.main.url(forResource: "stu", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(TodayCampusCatalog.self, from: data) else {
            errorMessage = "今日校园内置应用目录读取失败"
            return
        }
        localSections = catalog.datas
    }

    @MainActor
    private func loadCommunityApps() async {
        isLoadingCommunity = true
        defer { isLoadingCommunity = false }
        do {
            let fetched = try await OfficialCampusAPIClient.shared.fetchTodayCampusApps()
            let localPaths = Set(localSections.flatMap(\.apps).map { normalizedPath($0.openUrl) })
            communityApps = fetched.filter { !localPaths.contains(normalizedPath($0.url.absoluteString)) }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func normalizedPath(_ value: String) -> String {
        value
            .components(separatedBy: "stu.hfut.edu.cn/").last?
            .components(separatedBy: "?").first ?? value
    }

    private func openTodayCampusApp() {
        guard let appURL = URL(string: "cpdaily://") else { return }
        openURL(appURL) { accepted in
            if !accepted { openURL(studentPortalURL) }
        }
    }
}

private struct TodayCampusAppCard: View {
    let app: TodayCampusDisplayApp

    var body: some View {
        HStack(spacing: 9) {
            AsyncImage(url: app.iconURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Image(systemName: "square.grid.2x2.fill")
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                        .foregroundStyle(AppTheme.accent)
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(app.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .adaptiveGlass(cornerRadius: 14, tint: AppTheme.accent.opacity(0.04), interactive: true)
    }
}

private struct TodayCampusCatalog: Decodable {
    let datas: [TodayCampusLocalSection]
}

private struct TodayCampusLocalSection: Decodable, Identifiable {
    let categoryId: String
    let categoryName: String
    let apps: [TodayCampusLocalApp]
    var id: String { categoryId }
}

private struct TodayCampusLocalApp: Decodable {
    let appId: String
    let name: String
    let iconUrl: String
    let openUrl: String
}

private struct TodayCampusDisplayApp: Identifiable {
    let id: String
    let name: String
    let iconURL: URL?
    let url: URL

    init(_ app: TodayCampusLocalApp) {
        id = "local-\(app.appId)"
        name = app.name
        iconURL = URL(string: app.iconUrl)
        url = Self.secureStudentURL(app.openUrl)
    }

    init(_ app: OfficialTodayCampusApp) {
        id = "community-\(app.id)"
        name = app.name
        iconURL = app.logoURL
        url = Self.secureStudentURL(app.url.absoluteString)
    }

    private static func secureStudentURL(_ value: String) -> URL {
        let secure = value.replacingOccurrences(of: "http://stu.hfut.edu.cn", with: "https://stu.hfut.edu.cn")
        return URL(string: secure) ?? URL(string: "https://stu.hfut.edu.cn/")!
    }
}
