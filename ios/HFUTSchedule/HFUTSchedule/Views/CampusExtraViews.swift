import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

// MARK: - 慧新易校

/// 对应 Android 版 huiXin/HuiXin.kt：使用 synjones-auth 直接打开慧新易校平台。
struct HuiXinPortalView: View {
    @State private var url: URL?
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let url {
                PortalWebView(url: url)
            } else if isLoading {
                ProgressView("正在打开慧新易校…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label("慧新易校无法打开", systemImage: "building.2")
                } description: {
                    Text(errorMessage ?? "请先在“选项 → 安全登录”完成一次统一身份认证。")
                } actions: {
                    Button("重新登录慧新易校") { Task { await load(force: true) } }
                }
            }
        }
        .task { await load(force: false) }
    }

    @MainActor
    private func load(force: Bool) async {
        isLoading = url == nil
        errorMessage = nil
        do {
            if force { _ = try await CampusServiceClient.shared.refreshHuiXinToken() }
            url = try await CampusServiceClient.shared.huiXinPortalURL(path: "plat")
        } catch {
            errorMessage = error.localizedDescription
            url = nil
        }
        isLoading = false
    }
}

// MARK: - 校园邮箱

/// 对应 Android 版 one/mail/Mail.kt：拿到免登录链接后进入邮箱收件箱。
struct CampusMailPageView: View {
    @EnvironmentObject private var studentStore: AcademicStudentStore
    @Environment(\.openURL) private var openURL

    @State private var mailboxURL: URL?
    @State private var errorMessage: String?
    @State private var isLoading = true

    private var email: String {
        if let studentID = studentStore.info?.studentID, !studentID.isEmpty {
            return "\(studentID)@mail.hfut.edu.cn"
        }
        return "尚未获取到学号"
    }

    var body: some View {
        List {
            Section("邮箱账号") {
                LabeledContent("校园邮箱", value: email)
            }

            Section("登录邮箱") {
                if let mailboxURL {
                    NavigationLink {
                        PortalWebView(url: mailboxURL)
                    } label: {
                        Label("进入邮箱", systemImage: "envelope.open.fill")
                    }
                    Button {
                        openURL(mailboxURL)
                    } label: {
                        Label("在浏览器打开", systemImage: "safari")
                    }
                } else if isLoading {
                    HStack {
                        ProgressView()
                        Text("正在登录邮箱…").foregroundStyle(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(errorMessage ?? "校园邮箱尚未激活，或登录状态已失效。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("重新获取邮箱链接") { Task { await load(force: true) } }
                    }
                }
            }

            Section("使用说明") {
                Text("部分邮件内的链接在应用内无法跳转时，可选择「在浏览器打开」。")
                Button {
                    openURL(URL(string: "https://one.hfut.edu.cn/")!)
                } label: {
                    Label("首次使用请前往信息门户激活邮箱", systemImage: "arrow.up.right.square")
                }
            }
        }
        .navigationTitle("校园邮箱")
        .task { await load(force: false) }
    }

    @MainActor
    private func load(force: Bool) async {
        isLoading = mailboxURL == nil
        errorMessage = nil
        let schoolEmail = email.contains("@") ? email : ""
        guard !schoolEmail.isEmpty else {
            isLoading = false
            errorMessage = "请先在教务系统同步一次学籍信息，应用需要学号生成邮箱地址。"
            return
        }
        do {
            mailboxURL = try await CampusServiceClient.shared.fetchCampusMailURL(email: schoolEmail, forceRefresh: force)
            if mailboxURL == nil {
                errorMessage = "校方返回的邮箱链接为空，可能尚未激活校园邮箱。"
            }
        } catch {
            errorMessage = error.localizedDescription
            mailboxURL = nil
        }
        isLoading = false
    }
}

// MARK: - 作息（含校历入口）

/// 对应 Android 版 community/workRest/WorkAndRest.kt：学期 + 作息时间 + 线下课程，右上角跳转校历。
struct WorkRestView: View {
    @State private var overview: CommunityTermOverview?
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var calendarURL: URL?

    var body: some View {
        List {
            if let overview {
                termSection(overview)
                periodSection(overview)
                if !overview.offlineCourses.isEmpty {
                    offlineSection(overview)
                }
            } else if isLoading {
                HStack {
                    ProgressView()
                    Text("正在读取学期与作息…").foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(errorMessage ?? "作息数据读取失败。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("重新读取") { Task { await load() } }
                }
            }
        }
        .navigationTitle("作息")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let calendarURL {
                    NavigationLink {
                        PortalWebView(url: calendarURL)
                    } label: {
                        Text("校历")
                    }
                } else {
                    Button("校历") {
                        Task {
                            await CampusCloudConfigStore.shared.refreshIfNeeded(force: true)
                            calendarURL = CampusCloudConfigStore.shared.calendarURL
                        }
                    }
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private func termSection(_ overview: CommunityTermOverview) -> some View {
        Section("学期") {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(overview.termYear) 学年 第\(overview.termPeriod)学期")
                    .font(.headline)
                Text("\(overview.currentWeek) / \(overview.totalWeeks) 教学周")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("开始", value: overview.startDate)
            LabeledContent("结束", value: overview.endDate)
            LabeledContent("进度", value: progressText(overview))
            ProgressView(value: progressValue(overview))
        }
    }

    @ViewBuilder
    private func periodSection(_ overview: CommunityTermOverview) -> some View {
        Section("作息") {
            if overview.startTimes.count == overview.endTimes.count, !overview.startTimes.isEmpty {
                ForEach(Array(stride(from: 0, to: overview.startTimes.count, by: 2)), id: \.self) { index in
                    HStack {
                        periodRow(index: index, overview: overview)
                        if index + 1 < overview.startTimes.count {
                            Divider()
                            periodRow(index: index + 1, overview: overview)
                        }
                    }
                }
            } else if !overview.startTimes.isEmpty {
                LabeledContent("上课时间", value: overview.startTimes.joined(separator: "  "))
                LabeledContent("下课时间", value: overview.endTimes.joined(separator: "  "))
            } else {
                Text("校方暂未返回作息时间。").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func periodRow(index: Int, overview: CommunityTermOverview) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("第\(index + 1)节").font(.caption).foregroundStyle(.secondary)
            Text("\(overview.startTimes[index]) ~ \(overview.endTimes[index])")
                .font(.subheadline.weight(.medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func offlineSection(_ overview: CommunityTermOverview) -> some View {
        Section("线下课程（智慧社区数据源）") {
            ForEach(Array(overview.offlineCourses.enumerated()), id: \.element.id) { index, course in
                Button {
                    UIPasteboard.general.string = course.id
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(index + 1). \(course.name)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Text(course.className)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("学分 \(course.credit.formatted()) | \(course.id)\(course.type.map { " | \($0)" } ?? "")")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private func progressValue(_ overview: CommunityTermOverview) -> Double {
        guard let start = Self.dateFormatter.date(from: overview.startDate),
              let end = Self.dateFormatter.date(from: overview.endDate),
              end > start else { return 0 }
        let total = end.timeIntervalSince(start)
        let passed = Date().timeIntervalSince(start)
        return min(1, max(0, passed / total))
    }

    private func progressText(_ overview: CommunityTermOverview) -> String {
        guard let start = Self.dateFormatter.date(from: overview.startDate),
              let end = Self.dateFormatter.date(from: overview.endDate) else { return "—" }
        let now = Date()
        if now < start {
            let days = Calendar.current.dateComponents([.day], from: now, to: start).day ?? 0
            return "\(days) 天后开学"
        }
        if now >= end { return "本学期已结束" }
        return String(format: "已过 %.1f%%", progressValue(overview) * 100)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    @MainActor
    private func load() async {
        isLoading = overview == nil
        errorMessage = nil
        await CampusCloudConfigStore.shared.refreshIfNeeded()
        calendarURL = CampusCloudConfigStore.shared.calendarURL
        do {
            overview = try await CampusExtraAPIClient.shared.fetchTermOverview()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - 学费

/// 对应 Android 版 one/pay/Pay.kt：欠缴费用明细 + 缴费方式（含二维码）。
struct FeeCenterView: View {
    @EnvironmentObject private var studentStore: AcademicStudentStore
    @Environment(\.openURL) private var openURL

    @State private var arrears: CampusArrears = .empty
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showsQRCode = false

    var body: some View {
        List {
            Section("欠缴费用") {
                VStack(alignment: .leading, spacing: 2) {
                    Text("合计").font(.caption).foregroundStyle(.secondary)
                    Text("￥\(isLoading ? "—" : arrears.total)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                }
                .padding(.vertical, 4)

                LabeledContent("学费", value: "￥\(arrears.tuition)")
                LabeledContent("体检费", value: "￥\(arrears.physicalExamination)")
                LabeledContent("住宿费", value: "￥\(arrears.dormitory)")
                LabeledContent("军训费", value: "￥\(arrears.militaryTraining)")

                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.secondary)
                }
                if isLoading {
                    HStack { ProgressView(); Text("正在读取欠费信息…").foregroundStyle(.secondary) }
                }
            }

            Section("缴费方式") {
                VStack(alignment: .leading, spacing: 3) {
                    Label("银行卡预存", systemImage: "creditcard")
                    Text("提前在中国农业银行卡预存费用，开学后自动扣取。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button {
                    UIPasteboard.general.string = CampusExtraAPIClient.payFeeURLString
                } label: {
                    Label("网络支付：复制缴费链接", systemImage: "doc.on.doc")
                }
                Button {
                    showsQRCode.toggle()
                } label: {
                    Label("网络支付：显示二维码", systemImage: "qrcode")
                }
                if showsQRCode, let image = Self.qrImage(from: CampusExtraAPIClient.payFeeURLString) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 220)
                        .frame(maxWidth: .infinity)
                }
                Button {
                    openURL(CampusExtraAPIClient.payFeeURL)
                } label: {
                    Label("在浏览器打开缴费页面", systemImage: "safari")
                }
            }
        }
        .navigationTitle("费用中心")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("缴费") { openURL(CampusExtraAPIClient.payFeeURL) }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            arrears = try await CampusExtraAPIClient.shared.fetchArrears(studentID: studentStore.info?.studentID)
        } catch {
            errorMessage = "欠费信息读取失败：\(error.localizedDescription)"
        }
        isLoading = false
    }

    static func qrImage(from text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - 校园地图

/// 对应 Android 版 other/life/Map.kt：按校区分页展示校方地图图片。
struct CampusMapImagesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var maps: [CommunityCampusMap] = []
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        Group {
            if maps.isEmpty {
                if isLoading {
                    ProgressView("正在读取校园地图…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView {
                        Label("校园地图读取失败", systemImage: "map")
                    } description: {
                        Text(errorMessage ?? "校方暂未返回地图数据。")
                    } actions: {
                        Button("重新读取") { Task { await load() } }
                    }
                }
            } else {
                TabView {
                    ForEach(maps) { item in
                        ScrollView([.horizontal, .vertical]) {
                            AsyncImage(url: item.imageURL) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable().scaledToFit()
                                case .failure:
                                    ContentUnavailableView("地图加载失败", systemImage: "photo")
                                default:
                                    ProgressView()
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        }
                        .tabItem { Text(item.name) }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
            }
        }
        .navigationTitle("校园地图")
        .task { await load() }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let result = try await CampusExtraAPIClient.shared.fetchCampusMaps()
            let campusKeyword = appState.campus == .hefei ? "翡翠湖" : "宣城"
            maps = result.sorted { lhs, _ in lhs.name.contains(campusKeyword) }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - 教师查询

/// 对应 Android 版 school/teacherSearch：姓名 + 研究方向检索教师主页。
struct TeacherSearchView: View {
    @State private var name = ""
    @State private var direction = ""
    @State private var teachers: [CampusTeacher] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var hasSearched = false

    var body: some View {
        List {
            Section("检索条件") {
                TextField("教师姓名", text: $name)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("研究方向", text: $direction)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button {
                    Task { await search() }
                } label: {
                    Label("查询教师", systemImage: "magnifyingglass")
                }
                .disabled(isLoading)
            }

            if isLoading {
                HStack { ProgressView(); Text("正在查询教师…").foregroundStyle(.secondary) }
            } else if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.secondary)
            } else if hasSearched && teachers.isEmpty {
                Text("没有查询到符合条件的教师。").font(.footnote).foregroundStyle(.secondary)
            }

            if !teachers.isEmpty {
                Section("查询结果（\(teachers.count)）") {
                    ForEach(teachers) { teacher in
                        if let pageURL = CampusExtraAPIClient.teacherPageURL(teacher) {
                            NavigationLink {
                                PortalWebView(url: pageURL)
                            } label: {
                                TeacherRow(teacher: teacher)
                            }
                        } else {
                            TeacherRow(teacher: teacher)
                        }
                    }
                }
            }
        }
        .navigationTitle("教师查询")
        .task {
            if !hasSearched { await search() }
        }
    }

    @MainActor
    private func search() async {
        isLoading = true
        errorMessage = nil
        hasSearched = true
        do {
            teachers = try await CampusExtraAPIClient.shared.searchTeachers(name: name, direction: direction)
        } catch {
            errorMessage = "教师查询失败：\(error.localizedDescription)"
            teachers = []
        }
        isLoading = false
    }
}

private struct TeacherRow: View {
    let teacher: CampusTeacher

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: CampusExtraAPIClient.teacherPhotoURL(teacher)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Image(systemName: "person.crop.square")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.secondary)
                        .padding(12)
                }
            }
            .frame(width: 64, height: 78)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(teacher.name).font(.headline)
                if !teacher.department.isEmpty {
                    Text(teacher.department).font(.caption).foregroundStyle(.secondary)
                }
                if !teacher.roles.isEmpty {
                    Text(teacher.roles).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }
}

// MARK: - 转专业

/// 对应 Android 版 jxglstu/transfer：批次列表 + 批次内专业 + 我的申请。
struct TransferMajorView: View {
    @AppStorage("academicConnectionMode") private var connectionMode = AcademicConnectionMode.direct.rawValue
    @State private var batches: [TransferBatch] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            if isLoading {
                HStack { ProgressView(); Text("正在读取转专业批次…").foregroundStyle(.secondary) }
            } else if let errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(errorMessage).font(.footnote).foregroundStyle(.secondary)
                    Button("重新读取") { Task { await load() } }
                }
            } else if batches.isEmpty {
                Text("当前没有开放的转专业批次。").font(.footnote).foregroundStyle(.secondary)
            }

            ForEach(batches) { batch in
                NavigationLink {
                    TransferBatchDetailView(batch: batch)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(batch.title).font(.headline)
                        if !batch.applicationDate.isEmpty {
                            Text("申请 \(batch.applicationDate)").font(.caption).foregroundStyle(.secondary)
                        }
                        if !batch.admissionDate.isEmpty {
                            Text("录取 \(batch.admissionDate)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("转专业")
        .task { await load() }
        .refreshable { await load() }
    }

    @MainActor
    private func load() async {
        isLoading = batches.isEmpty
        errorMessage = nil
        do {
            let mode = AcademicConnectionMode(rawValue: connectionMode) ?? .direct
            let client = AcademicClient(mode: mode, cookies: CampusSessionStore.shared.allCookies)
            batches = try await client.fetchTransferBatches()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct TransferBatchDetailView: View {
    let batch: TransferBatch

    @AppStorage("academicConnectionMode") private var connectionMode = AcademicConnectionMode.direct.rawValue
    @State private var applications: [TransferApplication] = []
    @State private var myApplies: [TransferMyApply] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            if !myApplies.isEmpty {
                Section("我的申请") {
                    ForEach(myApplies) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.major).font(.subheadline.weight(.medium))
                            Text(item.department).font(.caption).foregroundStyle(.secondary)
                            Text(item.status).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            if isLoading {
                HStack { ProgressView(); Text("正在读取专业列表…").foregroundStyle(.secondary) }
            } else if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.secondary)
            }

            if !applications.isEmpty {
                Section("可申请专业（\(applications.count)）") {
                    ForEach(applications) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.major).font(.subheadline.weight(.semibold))
                            Text(item.department).font(.caption).foregroundStyle(.secondary)
                            if !item.applyStart.isEmpty || !item.applyEnd.isEmpty {
                                Text("申请时间 \(Self.short(item.applyStart)) ~ \(Self.short(item.applyEnd))")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Text("计划 \(item.preparedCount) 人 · 已报名 \(item.applyCount) 人")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            if !item.conditions.isEmpty {
                                Text(item.conditions).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle(batch.title)
        .task { await load() }
    }

    private static func short(_ text: String) -> String {
        text.replacingOccurrences(of: "T", with: " ").components(separatedBy: ".").first ?? text
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let mode = AcademicConnectionMode(rawValue: connectionMode) ?? .direct
            let client = AcademicClient(mode: mode, cookies: CampusSessionStore.shared.allCookies)
            async let list = client.fetchTransferApplications(batchID: batch.batchID)
            async let mine = client.fetchMyTransferApplications(batchID: batch.batchID)
            applications = try await list
            myApplies = (try? await mine) ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - 网址导航

/// 对应 Android 版 my/webLab/WebUI.kt：浏览器 + 收藏夹 + 实验室。
struct CloudWebNavigationView: View {
    struct Favorite: Codable, Identifiable, Hashable {
        var id = UUID()
        var name: String
        var url: String
    }

    @Environment(\.openURL) private var openURL
    @State private var input = "https://"
    @State private var favorites: [Favorite] = []
    @State private var laboratories: [CampusCloudLab] = []
    @State private var showsQRCode = false
    @State private var showsAddFavorite = false
    @State private var newName = ""
    @State private var newURL = "https://"
    @State private var openedURL: URL?

    private static let favoritesKey = "webNavigationFavoritesV1"

    var body: some View {
        List {
            Section("浏览器") {
                TextField("输入链接", text: $input)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                if let url = normalizedInput {
                    Button {
                        openedURL = url
                    } label: {
                        Label("在应用内打开", systemImage: "arrow.right.circle.fill")
                    }
                    Button {
                        showsQRCode.toggle()
                    } label: {
                        Label("显示二维码", systemImage: "qrcode")
                    }
                    if showsQRCode, let image = FeeCenterView.qrImage(from: url.absoluteString) {
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 200)
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            Section("收藏夹") {
                if favorites.isEmpty {
                    Text("开始添加你的网页收藏夹，或在打开网页时点击右上角加号。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(favorites) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        Button {
                            if let url = URL(string: item.url) { openedURL = url }
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Label(item.name, systemImage: "star.fill")
                                Text(item.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        HStack(spacing: 12) {
                            Button("复制") { UIPasteboard.general.string = item.url }
                            Button("分享") { share(item.url) }
                            Button("删除", role: .destructive) { delete(item) }
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                }
            }

            if !laboratories.isEmpty {
                Section("实验室") {
                    ForEach(laboratories) { lab in
                        Button {
                            openedURL = lab.url
                        } label: {
                            Label(lab.title, systemImage: "network")
                                .font(.subheadline)
                        }
                    }
                }
            }
        }
        .navigationTitle("网址导航")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newName = ""
                    newURL = normalizedInput?.absoluteString ?? "https://"
                    showsAddFavorite = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .navigationDestination(item: $openedURL) { url in
            PortalWebView(url: url)
        }
        .sheet(isPresented: $showsAddFavorite) {
            NavigationStack {
                Form {
                    TextField("名称", text: $newName)
                    TextField("链接", text: $newURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Text("请输入 http:// 或 https:// 开头的完整链接")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .navigationTitle("添加收藏")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showsAddFavorite = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") { saveFavorite() }
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || normalized(newURL) == nil)
                    }
                }
            }
        }
        .task { await load() }
    }

    private var normalizedInput: URL? { normalized(input) }

    private func normalized(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "https://", trimmed != "http://" else { return nil }
        let candidate = trimmed.hasPrefix("http") ? trimmed : "http://\(trimmed)"
        guard let url = URL(string: candidate), let host = url.host, host.contains(".") else { return nil }
        return url
    }

    private func share(_ text: String) {
        let activity = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.keyWindow?.rootViewController else { return }
        root.present(activity, animated: true)
    }

    private func saveFavorite() {
        guard let url = normalized(newURL) else { return }
        let name = newName.trimmingCharacters(in: .whitespaces)
        favorites.append(Favorite(name: name.isEmpty ? url.host ?? "网页" : name, url: url.absoluteString))
        persistFavorites()
        showsAddFavorite = false
    }

    private func delete(_ item: Favorite) {
        favorites.removeAll { $0.id == item.id }
        persistFavorites()
    }

    private func persistFavorites() {
        if let data = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(data, forKey: Self.favoritesKey)
        }
    }

    @MainActor
    private func load() async {
        if let data = UserDefaults.standard.data(forKey: Self.favoritesKey),
           let saved = try? JSONDecoder().decode([Favorite].self, from: data) {
            favorites = saved
        }
        await CampusCloudConfigStore.shared.refreshIfNeeded()
        laboratories = CampusCloudConfigStore.shared.laboratories
    }
}

// MARK: - 培养方案

/// 培养方案：按模块展示学分与课程数，支持搜索（对应 Android 版 ProgramUI）。
struct ProgramPlanView: View {
    @AppStorage("academicConnectionMode") private var connectionMode = AcademicConnectionMode.direct.rawValue
    @State private var modules: [AcademicProgramSummary] = []
    @State private var keyword = ""
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var filtered: [AcademicProgramSummary] {
        let trimmed = keyword.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return modules }
        return modules.filter { module in
            module.title.localizedCaseInsensitiveContains(trimmed)
                || (module.remark ?? "").localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var totalCredits: Double {
        modules.compactMap(\.requiredCredits).reduce(0, +)
    }

    private var totalCourses: Int {
        modules.reduce(0) { $0 + $1.courseCount }
    }

    var body: some View {
        List {
            if modules.isEmpty, isLoading {
                HStack { ProgressView(); Text("正在读取培养方案…").foregroundStyle(.secondary) }
            } else if let errorMessage, modules.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(errorMessage).font(.footnote).foregroundStyle(.secondary)
                    Button("重新读取") { Task { await load() } }
                }
            } else {
                Section("方案概览") {
                    LabeledContent("模块", value: "\(modules.count) 个")
                    LabeledContent("要求学分", value: totalCredits > 0 ? totalCredits.formatted() : "—")
                    LabeledContent("计划课程", value: "\(totalCourses) 门")
                }

                Section("模块（\(filtered.count)）") {
                    ForEach(filtered) { module in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(module.title).font(.subheadline.weight(.semibold))
                            Text([
                                module.requiredCredits.map { "要求 \($0.formatted()) 学分" },
                                module.courseCount > 0 ? "\(module.courseCount) 门课程" : nil
                            ].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let remark = module.remark, !remark.isEmpty {
                                Text(remark).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .searchable(text: $keyword, prompt: "搜索模块或课程")
        .navigationTitle("培养方案")
        .task { if modules.isEmpty { await load() } }
        .refreshable { await load() }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let mode = AcademicConnectionMode(rawValue: connectionMode) ?? .direct
            modules = try await AcademicClient(mode: mode, cookies: CampusSessionStore.shared.allCookies).fetchProgram()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - 学期报告

/// 学期报告：学业 / 成绩 / 生活 / 图书馆四段式，对应 Android 版 TermReportScreen。
struct TermReportView: View {
    @EnvironmentObject private var scheduleStore: ScheduleStore
    @EnvironmentObject private var recordsStore: AcademicRecordsStore
    @EnvironmentObject private var studentStore: AcademicStudentStore

    @State private var cardBalance: Double?
    @State private var borrowCount: Int?
    @State private var isLoading = true

    private var courseNames: [String] {
        Array(Set(scheduleStore.courses.map(\.name))).sorted()
    }

    private var credits: Double {
        scheduleStore.courses.compactMap { $0.details?.credits }.reduce(0, +)
    }

    private var currentGrades: [AcademicGrade] {
        recordsStore.gradeTerms.max { $0.term < $1.term }?.grades ?? []
    }

    private var numericScores: [(AcademicGrade, Double)] {
        currentGrades.compactMap { grade in
            guard let value = Double(grade.score.filter { "0123456789.".contains($0) }) else { return nil }
            return (grade, value)
        }
    }

    var body: some View {
        List {
            Section("学业报告") {
                LabeledContent("本学期课程", value: "\(courseNames.count) 门")
                LabeledContent("课程安排", value: "\(scheduleStore.courses.count) 条")
                LabeledContent("上课地点", value: "\(Set(scheduleStore.courses.map(\.location).filter { !$0.isEmpty }).count) 处")
                if credits > 0 { LabeledContent("已同步学分", value: credits.formatted()) }
            }

            Section("成绩分析") {
                if numericScores.isEmpty {
                    Text("暂无成绩数据，可在“成绩”页面同步后再查看。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    let average = numericScores.map(\.1).reduce(0, +) / Double(numericScores.count)
                    LabeledContent("平均分", value: String(format: "%.2f", average))
                    LabeledContent("课程数", value: "\(numericScores.count) 门")
                    if let best = numericScores.max(by: { $0.1 < $1.1 }) {
                        LabeledContent("最高分", value: "\(best.0.courseName) \(best.0.score)")
                    }
                    let failed = numericScores.filter { $0.1 < 60 }
                    LabeledContent("挂科门数", value: "\(failed.count) 门")
                }
            }

            Section("生活报告") {
                LabeledContent("一卡通余额", value: cardBalance.map { String(format: "￥%.2f", $0) } ?? "—")
                LabeledContent("图书馆在借", value: borrowCount.map { "\($0) 本" } ?? "—")
                LabeledContent("校区", value: studentStore.info?.campus.isEmpty == false ? studentStore.info!.campus : "—")
            }

            Section("学生信息") {
                if let info = studentStore.info {
                    LabeledContent("姓名", value: info.name)
                    LabeledContent("学号", value: info.studentID)
                    LabeledContent("学院", value: info.department.isEmpty ? "—" : info.department)
                    LabeledContent("专业", value: info.major.isEmpty ? "—" : info.major)
                    LabeledContent("班级", value: info.className.isEmpty ? "—" : info.className)
                } else {
                    Text("尚未同步学籍信息。").font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section {
                Text("报告使用本机已同步的课表、成绩与校园服务数据生成，不会上传个人数据。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("学期报告")
        .overlay { if isLoading { ProgressView().controlSize(.small) } }
        .task { await load() }
        .refreshable { await load() }
    }

    @MainActor
    private func load() async {
        isLoading = true
        if let cards = try? await CampusServiceClient.shared.fetchCampusCards(), let first = cards.first {
            cardBalance = first.balance
        } else if let cached = CampusServiceClient.shared.cachedCampusCardBalance {
            cardBalance = cached
        }
        if let records = try? await CampusServiceClient.shared.fetchLibraryBorrowRecords() {
            borrowCount = records.count
        }
        isLoading = false
    }
}
