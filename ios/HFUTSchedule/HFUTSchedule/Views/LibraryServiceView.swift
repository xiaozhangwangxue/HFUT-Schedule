import SwiftUI

struct LibraryServiceView: View {
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            LibraryMineView(openSearch: { selection = 1 })
                .tag(0)
                .tabItem { Label("我", systemImage: selection == 0 ? "person.fill" : "person") }
            LibrarySearchView()
                .tag(1)
                .tabItem { Label("搜索", systemImage: "magnifyingglass") }
        }
    }
}

private struct LibraryMineView: View {
    @AppStorage("academicConnectionMode") private var connectionMode = AcademicConnectionMode.direct.rawValue
    @State private var status = LibraryStatusSummary()
    @State private var records: [LibraryBorrowRecord] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    let openSearch: () -> Void

    private var outstanding: [LibraryBorrowRecord] { records.filter { $0.status == "2" || $0.status == "02" } }
    private var nextDue: LibraryBorrowRecord? {
        outstanding.filter { $0.returnTime != nil }.sorted { ($0.returnTime ?? "") < ($1.returnTime ?? "") }.first
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                Text("状态").font(.headline).padding(.horizontal, 4)
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(outstanding.isEmpty ? "无待归还书籍" : "待归还 \(outstanding.count) 本")
                                .font(.title3.bold())
                            if let nextDue {
                                Text("最近应还：\(nextDue.returnTime?.split(separator: " ").first.map(String.init) ?? "未知")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: outstanding.contains(where: { $0.status == "02" }) ? "exclamationmark.circle.fill" : "books.vertical.fill")
                            .font(.title2)
                            .foregroundStyle(outstanding.contains(where: { $0.status == "02" }) ? .red : AppTheme.accent)
                    }
                    .padding()
                    Divider().padding(.horizontal)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 0) {
                        LibraryMetric(title: "借阅", value: "\(status.borrowCount) 本", icon: "book.closed.fill")
                        LibraryMetric(title: "预约", value: "\(status.reserveCount) 本", icon: "calendar.badge.clock")
                        LibraryMetric(title: "收藏", value: "\(status.collectCount) 条", icon: "bookmark.fill")
                        LibraryMetric(title: "书架", value: "\(status.bookShelfCount) 本", icon: "books.vertical.fill")
                    }
                }
                .adaptiveGlass(cornerRadius: 24)

                if !records.isEmpty {
                    NavigationLink {
                        LibraryBorrowedView(records: records)
                    } label: {
                        HStack {
                            Label("借阅图书记录", systemImage: "clock.arrow.circlepath")
                            Spacer()
                            Text("\(records.count) 本").foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding()
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .adaptiveGlass(cornerRadius: 18, interactive: true)
                }

                Text("选项").font(.headline).padding(.horizontal, 4)
                VStack(spacing: 0) {
                    Button(action: openSearch) {
                        LibraryOptionRow(title: "搜索", subtitle: "智慧社区与斛兵知搜双来源", icon: "magnifyingglass")
                    }
                    Divider().padding(.leading, 56)
                    LibraryPortalLink(title: "更多", subtitle: "新图书馆官网（有时需校园网）", icon: "globe", url: "https://lib.hfut.edu.cn/", mode: mode)
                    Divider().padding(.leading, 56)
                    LibraryPortalLink(title: "续借、预约等服务", subtitle: "旧图书馆官网（需校园网）", icon: "arrow.clockwise.circle", url: "http://210.45.242.5:8080/", mode: mode)
                    Divider().padding(.leading, 56)
                    LibraryPortalLink(title: "座位预约", subtitle: "合肥校区（需校园网）", icon: "chair.lounge.fill", url: "http://210.45.242.57/home/web/f_second", mode: mode)
                    Divider().padding(.leading, 56)
                    LibraryPortalLink(title: "研讨间预约", subtitle: "合肥与宣城校区（需校园网）", icon: "person.3.fill", url: "http://210.45.243.31:81", mode: mode)
                }
                .buttonStyle(.plain)
                .adaptiveGlass(cornerRadius: 24)

                if let errorMessage {
                    ContentUnavailableView("图书馆数据读取失败", systemImage: "books.vertical", description: Text(errorMessage))
                }
            }
            .padding()
        }
        .overlay { if isLoading { ProgressView("正在读取图书馆账户…").padding().adaptiveGlass(cornerRadius: 18) } }
        .task { await load() }
        .refreshable { await load(force: true) }
    }

    private var mode: AcademicConnectionMode { AcademicConnectionMode(rawValue: connectionMode) ?? .direct }

    @MainActor private func load(force: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            if force { _ = try await CampusServiceClient.shared.refreshLibraryToken() }
            let loadedStatus = try await CampusServiceClient.shared.fetchLibraryStatus()
            let loadedRecords = try await CampusServiceClient.shared.fetchLibraryBorrowRecords(pageSize: max(loadedStatus.borrowCount, 30))
            status = loadedStatus
            records = loadedRecords.sorted { $0.createdTime > $1.createdTime }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct LibraryMetric: View {
    let title: String
    let value: String
    let icon: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(AppTheme.accent).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.headline)
            }
            Spacer(minLength: 0)
        }
        .padding()
    }
}

private struct LibraryOptionRow: View {
    let title: String
    let subtitle: String
    let icon: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(AppTheme.accent).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding()
        .contentShape(Rectangle())
    }
}

private struct LibraryPortalLink: View {
    let title: String
    let subtitle: String
    let icon: String
    let url: String
    let mode: AcademicConnectionMode
    var body: some View {
        if let original = URL(string: url) {
            NavigationLink {
                PortalWebView(url: WebVPNURLConverter.convertedIfNeeded(original, mode: mode))
                    .navigationTitle(title)
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                LibraryOptionRow(title: title, subtitle: subtitle, icon: icon)
            }
        }
    }
}

private struct LibraryBorrowedView: View {
    let records: [LibraryBorrowRecord]

    var body: some View {
        List {
            Section {
                HStack {
                    LibraryCount(title: "总计", value: records.count)
                    LibraryCount(title: "已归还", value: records.filter { $0.status == "0" }.count)
                    LibraryCount(title: "借阅中", value: records.filter { $0.status == "2" }.count)
                    LibraryCount(title: "逾期", value: records.filter { $0.status == "02" }.count)
                }
            }
            ForEach(records) { record in
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(record.libraryDetail.detail.title).font(.headline)
                            Spacer()
                            Text(record.statusText).font(.caption.bold())
                                .foregroundStyle(record.status == "02" ? .red : .secondary)
                        }
                        Text(record.location).font(.subheadline).foregroundStyle(.secondary)
                        Text("借于 \(record.createdTime)\n\(record.status == "0" ? "还于 \(record.realReturnTime ?? "未知")" : "应还 \(record.returnTime ?? "未知")")")
                            .font(.caption)
                        Divider()
                        Text("\(record.libraryDetail.detail.authors) · \(record.libraryDetail.detail.publishers)（\(record.libraryDetail.detail.year)）")
                            .font(.caption)
                        Text("ISBN \(record.libraryDetail.detail.isbn) · 索书号 \(record.callNo)")
                            .font(.caption2).foregroundStyle(.tertiary)
                        if !record.libraryDetail.detail.digest.isEmpty {
                            Text(record.libraryDetail.detail.digest).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            Section { Text("续借请前往旧图书馆官网（校园网）").font(.caption).foregroundStyle(.secondary) }
        }
        .navigationTitle("借阅图书")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LibraryCount: View {
    let title: String
    let value: Int
    var body: some View {
        VStack(spacing: 4) { Text(title).font(.caption).foregroundStyle(.secondary); Text("\(value)").font(.headline) }
            .frame(maxWidth: .infinity)
    }
}

private struct LibrarySearchView: View {
    private enum Source: String, CaseIterable { case community = "智慧社区"; case discovery = "斛兵知搜" }
    @State private var source = Source.community
    @State private var query = ""
    @State private var communityBooks: [CommunityLibraryBook] = []
    @State private var discoveryBooks: [OfficialLibraryBook] = []
    @State private var page = 1
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedCommunityBook: CommunityLibraryBook?
    @State private var selectedDiscoveryBook: OfficialLibraryBook?

    var body: some View {
        VStack(spacing: 10) {
            Picker("检索来源", selection: $source) {
                ForEach(Source.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            HStack {
                TextField(source == .community ? "搜索馆藏" : "搜索馆藏与电子书", text: $query)
                    .textFieldStyle(.plain)
                    .submitLabel(.search)
                    .onSubmit { Task { await search(resetPage: true) } }
                Button { Task { await search(resetPage: true) } } label: { Image(systemName: "magnifyingglass") }
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
            }
            .padding()
            .adaptiveGlass(cornerRadius: 16, interactive: true)
            .padding(.horizontal)

            List {
                if source == .community {
                    ForEach(communityBooks) { book in
                        Button { selectedCommunityBook = book } label: { CommunityBookRow(book: book) }
                            .buttonStyle(.plain)
                    }
                } else {
                    ForEach(discoveryBooks) { book in
                        Button { selectedDiscoveryBook = book } label: { DiscoveryBookRow(book: book) }
                            .buttonStyle(.plain)
                    }
                }
                if let errorMessage {
                    ContentUnavailableView("图书检索失败", systemImage: "books.vertical", description: Text(errorMessage))
                }
            }
            .listStyle(.plain)
            .overlay {
                if isLoading { ProgressView("正在检索馆藏…") }
                else if communityBooks.isEmpty && discoveryBooks.isEmpty && errorMessage == nil {
                    ContentUnavailableView("搜索图书", systemImage: "text.magnifyingglass", description: Text("输入书名、作者或 ISBN"))
                }
            }

            HStack {
                Button("上一页", systemImage: "chevron.left") { page -= 1; Task { await search() } }.disabled(page <= 1 || isLoading)
                Spacer()
                Text("第 \(page) 页").font(.subheadline.bold())
                Spacer()
                Button("下一页", systemImage: "chevron.right") { page += 1; Task { await search() } }.disabled(isLoading)
            }
            .padding(.horizontal, 24).padding(.bottom, 8)
        }
        .onChange(of: source) { _, _ in communityBooks = []; discoveryBooks = []; page = 1; errorMessage = nil }
        .sheet(item: $selectedCommunityBook) { CommunityBookDetail(book: $0) }
        .sheet(item: $selectedDiscoveryBook) { DiscoveryBookDetail(book: $0) }
    }

    @MainActor private func search(resetPage: Bool = false) async {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }
        if resetPage { page = 1 }
        isLoading = true; errorMessage = nil
        do {
            if source == .community {
                communityBooks = try await OfficialCampusAPIClient.shared.searchCommunityLibrary(keyword: keyword, page: page)
                discoveryBooks = []
            } else {
                discoveryBooks = try await OfficialCampusAPIClient.shared.searchLibrary(keyword: keyword, page: page)
                communityBooks = []
            }
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }
}

private struct CommunityBookRow: View {
    let book: CommunityLibraryBook
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(book.name).font(.headline)
            Text("索书号 \(book.callNumber)").font(.caption).foregroundStyle(.secondary)
            Text([book.author, book.publisher, book.year].compactMap { $0 }.joined(separator: " · "))
                .font(.caption2).foregroundStyle(.tertiary)
        }.padding(.vertical, 5)
    }
}

private struct DiscoveryBookRow: View {
    let book: OfficialLibraryBook
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(book.title.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)).font(.headline)
            Text("ISBN \(book.isbn)").font(.caption).foregroundStyle(.secondary)
            Text([book.author.joined(separator: "、"), book.publishers, String(book.year)].compactMap { $0 }.joined(separator: " · "))
                .font(.caption2).foregroundStyle(.tertiary)
            if let origin = book.ds?.map(\.tName).joined(separator: "、"), !origin.isEmpty { Text(origin).font(.caption2).foregroundStyle(.secondary) }
        }.padding(.vertical, 5)
    }
}

private struct CommunityBookDetail: View {
    let book: CommunityLibraryBook
    @Environment(\.dismiss) private var dismiss
    @State private var positions: [CommunityLibraryPosition] = []
    @State private var errorMessage: String?
    var body: some View {
        NavigationStack {
            List {
                Section("索书号 \(book.callNumber)") {
                    ForEach(positions) { position in LabeledContent(position.place, value: position.status) }
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.secondary) }
            }
            .navigationTitle(book.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("完成") { dismiss() } }
            .task {
                do { positions = try await OfficialCampusAPIClient.shared.fetchCommunityLibraryPositions(callNumber: book.callNumber) }
                catch { errorMessage = error.localizedDescription }
            }
        }
    }
}

private struct DiscoveryBookDetail: View {
    let book: OfficialLibraryBook
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("图书信息") {
                    LabeledContent("作者", value: book.author.joined(separator: "、"))
                    LabeledContent("出版社", value: book.publishers ?? "未知")
                    LabeledContent("年份", value: String(book.year))
                    LabeledContent("ISBN", value: book.isbn)
                    if let abstract = book.abstract, !abstract.isEmpty { Text(abstract.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)) }
                }
                Section("馆藏位置") {
                    ForEach(Array((book.gc ?? []).enumerated()), id: \.offset) { _, place in
                        VStack(alignment: .leading) {
                            Text(place.in)
                            Text("索书号 \(place.cp) · \(place.js ?? "馆藏")").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(book.title.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("完成") { dismiss() } }
        }
    }
}
