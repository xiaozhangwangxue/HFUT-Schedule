import SwiftUI

struct FeatureDetailView: View {
    let feature: CampusFeature
    @AppStorage("academicConnectionMode") private var connectionMode = AcademicConnectionMode.direct.rawValue

    private var selectedConnectionMode: AcademicConnectionMode {
        AcademicConnectionMode(rawValue: connectionMode) ?? .direct
    }

    var body: some View {
        Group {
            switch feature.nativeDestination {
            case .scanner:
                ScannerView()
            case .schedule:
                ScheduleView()
            case .calendar:
                NativeCampusCalendarView()
            case .workRest:
                WorkRestView()
            case .notifications:
                NotificationsView()
            case .settings:
                ProfileView()
            case .grades:
                AcademicRecordsView(kind: .grades)
            case .exams:
                AcademicRecordsView(kind: .exams)
            case .personInfo:
                AcademicStudentInfoView()
            case .courseSearch:
                OfficialCourseSearchView()
            case .classrooms:
                OfficialClassroomSearchView()
            case .failRate:
                OfficialFailRateView()
            case .campusCard:
                CampusCardServiceView()
            case .electricity:
                ElectricityServiceView()
            case .campusNetwork:
                CampusNetworkServiceView()
            case .bathing:
                BathingServiceView()
            case .laundry:
                LaundryServiceView()
            case .secondClass:
                SecondClassServiceView()
            case .courseSummary:
                NativeCourseSummaryView()
            case .dormitory:
                NativeDormitoryView()
            case .program:
                ProgramPlanView()
            case .library:
                LibraryServiceView()
            case .campusLife:
                NativeCampusLifeView()
            case .holidays:
                NativeHolidayView()
            case .express:
                NativeExpressView()
            case .appointment:
                NativeAppointmentView()
            case .repair:
                NativeRepairView()
            case .campusMail:
                CampusMailPageView()
            case .webNavigation:
                CloudWebNavigationView()
            case .courseSelection:
                AcademicCourseSelectionView()
            case .teachingSurvey:
                AcademicTeachingSurveyView()
            case .webVPN:
                NativeWebVPNView()
            case .todayCampus:
                TodayCampusView()
            case .huiXin:
                HuiXinPortalView()
            case .fee:
                FeeCenterView()
            case .teacherSearch:
                TeacherSearchView()
            case .transferMajor:
                TransferMajorView()
            case nil:
                portalOrUnavailable
            }
        }
        .navigationTitle(feature.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var portalOrUnavailable: some View {
        if let originalURL = feature.url {
            let url = WebVPNURLConverter.convertedIfNeeded(originalURL, mode: selectedConnectionMode)
            if ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                PortalWebView(url: url)
            } else {
                ExternalLinkView(feature: feature, url: url)
            }
        } else {
            ContentUnavailableView(
                feature.title,
                systemImage: feature.systemImage,
                description: Text("此原生模块正在从 Android 迁移到 SwiftUI。")
            )
        }
    }
}

private struct CampusMailView: View {
    private let portalURL = URL(string: "https://one.hfut.edu.cn/home/index")!

    var body: some View {
        PortalWebView(url: portalURL, autoOpenCampusMailbox: true)
    }
}

private struct NativeWebVPNView: View {
    @AppStorage("academicConnectionMode") private var connectionMode = AcademicConnectionMode.direct.rawValue
    @State private var hasSession = false

    var body: some View {
        List {
            Section("校外访问状态") {
                Label(hasSession ? "已保存 WebVPN 会话" : "尚未登录 WebVPN", systemImage: hasSession ? "checkmark.shield.fill" : "lock.shield")
                    .foregroundStyle(hasSession ? .green : .secondary)
                Picker("教务连接方式", selection: $connectionMode) {
                    ForEach(AcademicConnectionMode.allCases) { mode in Text(mode.title).tag(mode.rawValue) }
                }
            }
            Section("登录") {
                SourceAnchoredNavigationLink(sourceID: "webvpn-login") {
                    PortalWebView(url: URL(string: "https://webvpn.hfut.edu.cn/login?cas_login=true")!)
                } label: {
                    Label(hasSession ? "打开 WebVPN 门户" : "使用统一身份认证登录", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
            Section("使用说明") {
                Text("登录成功后，应用会保存 WebVPN 与统一身份认证 Cookie；选择“校外 WebVPN”后，教务及校内网页会自动通过 WebVPN 访问，无需每个栏目重复登录。")
            }
        }
        .onAppear { refreshStatus() }
        .onChange(of: connectionMode) { _, value in
            if value == AcademicConnectionMode.webVPN.rawValue { refreshStatus() }
        }
    }

    private func refreshStatus() {
        hasSession = CampusSessionStore.shared.allCookies.contains {
            $0.domain.lowercased().contains("webvpn.hfut.edu.cn")
        }
    }
}

private struct NativeWebNavigationView: View {
    private struct Favorite: Codable, Identifiable, Hashable {
        var id = UUID()
        let name: String
        let url: String
    }

    @State private var input = "https://"
    @State private var favorites: [Favorite] = []
    @State private var showingAdd = false
    @State private var addName = ""
    @State private var addURL = "https://"

    var body: some View {
        List {
            Section("浏览器") {
                TextField("输入链接", text: $input)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if let url = normalizedURL(input) {
                    SourceAnchoredNavigationLink(sourceID: "web-navigation-open") {
                        PortalWebView(url: url)
                    } label: {
                        Label("打开网页", systemImage: "arrow.right.circle.fill")
                    }
                }
            }

            Section("收藏夹") {
                if favorites.isEmpty {
                    ContentUnavailableView(
                        "开始添加你的网页收藏夹",
                        systemImage: "star",
                        description: Text("点击右上角加号手动添加")
                    )
                }
                ForEach(favorites) { item in
                    if let url = URL(string: item.url) {
                        SourceAnchoredNavigationLink(sourceID: "web-favorite-\(item.id.uuidString)") {
                            PortalWebView(url: url)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Label(item.name, systemImage: "star.fill")
                                Text(item.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
                .onDelete(perform: deleteFavorites)
            }

            Section("实验室") {
                Label("实验室项目会随原项目在线配置更新", systemImage: "network")
                    .foregroundStyle(.secondary)
                Link("原项目实验室", destination: URL(string: "https://chiu-xah.github.io/")!)
            }
        }
        .toolbar {
            Button("添加收藏", systemImage: "plus") { showingAdd = true }
        }
        .sheet(isPresented: $showingAdd) {
            NavigationStack {
                Form {
                    TextField("名称", text: $addName)
                    TextField("https://…", text: $addURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .navigationTitle("添加网页")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { showingAdd = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") { saveFavorite() }
                            .disabled(addName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || normalizedURL(addURL) == nil)
                    }
                }
            }
        }
        .onAppear(perform: loadFavorites)
    }

    private func normalizedURL(_ text: String) -> URL? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let completed = value.contains("://") ? value : "https://\(value)"
        guard let url = URL(string: completed), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    private func saveFavorite() {
        guard let url = normalizedURL(addURL) else { return }
        favorites.insert(Favorite(name: addName.trimmingCharacters(in: .whitespacesAndNewlines), url: url.absoluteString), at: 0)
        persistFavorites()
        addName = ""
        addURL = "https://"
        showingAdd = false
    }

    private func deleteFavorites(at offsets: IndexSet) {
        favorites.remove(atOffsets: offsets)
        persistFavorites()
    }

    private func loadFavorites() {
        guard let data = UserDefaults.standard.data(forKey: "web-navigation-favorites") else { return }
        favorites = (try? JSONDecoder().decode([Favorite].self, from: data)) ?? []
    }

    private func persistFavorites() {
        if let data = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(data, forKey: "web-navigation-favorites")
        }
    }
}

/// Mirrors Android RepairWindow: a campus-prioritized chooser that opens the
/// two official logistics sites externally instead of embedding one campus.
private struct NativeRepairView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openURL) private var openURL

    private struct Site: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let url: URL
    }

    private var sites: [Site] {
        let hefei = Site(
            id: "hefei",
            title: "智慧后勤-合肥校区",
            subtitle: "座位预约、报修等服务",
            url: URL(string: "http://zhhq.hfut.edu.cn/school/")!
        )
        let xuancheng = Site(
            id: "xuancheng",
            title: "智慧后勤-宣城校区",
            subtitle: "宣城校区后勤与报修",
            url: URL(string: "http://xcfw.hfut.edu.cn/school/")!
        )
        return appState.campus == .xuancheng ? [xuancheng, hefei] : [hefei, xuancheng]
    }

    var body: some View {
        List {
            Section {
                ForEach(sites) { site in
                    Button {
                        openURL(site.url)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "network")
                                .font(.title3)
                                .frame(width: 30)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(site.title).font(.headline)
                                Text(site.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("与 Android 原版一致，选择校区后使用系统浏览器打开官方智慧后勤。")
            }
        }
    }
}

/// The Android upstream currently exposes this destination as a native
/// developing screen and does not publish a venue-reservation API yet.
private struct NativeAppointmentView: View {
    var body: some View {
        ContentUnavailableView(
            "功能开发中",
            systemImage: "table.furniture",
            description: Text("场地预约暂未开放。")
        )
    }
}

private struct NativeCourseSummaryView: View {
    @EnvironmentObject private var scheduleStore: ScheduleStore
    @State private var query = ""

    private var courses: [Course] {
        let unique = Dictionary(grouping: scheduleStore.courses, by: { $0.details?.code ?? $0.name })
            .compactMap { $0.value.first }
        return unique.filter { query.isEmpty || "\($0.name) \($0.teacher) \($0.details?.code ?? "")".localizedCaseInsensitiveContains(query) }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        List(courses) { course in
            SourceAnchoredNavigationLink(sourceID: "course-summary-\(course.id.uuidString)") {
                CourseDetailView(course: course)
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(course.name).font(.headline)
                    Text([course.details?.code, course.details?.type, course.details?.credits.map { "\($0) 学分" }, course.teacher.isEmpty ? nil : course.teacher].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(course.details?.scheduleText ?? "\(course.weekdayName) \(course.startTime)-\(course.endTime) \(course.location)")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .searchable(text: $query, prompt: "课程名、教师或课程代码")
        .overlay { if courses.isEmpty { ContentUnavailableView("暂无课程", systemImage: "books.vertical", description: Text("请先在安全登录中同步本学期课表。")) } }
    }
}

private struct NativeDormitoryView: View {
    @State private var dormitory: OfficialDormitory?
    @State private var members: [OfficialDormitoryMember] = []
    @State private var scores: [OfficialDormitoryScore] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let dormitory {
                Section("寝室信息") {
                    LabeledContent("校区", value: dormitory.campus)
                    LabeledContent("楼栋", value: dormitory.dormitory)
                    LabeledContent("房间", value: dormitory.room)
                }
                Section("寝室成员") {
                    ForEach(members) { member in LabeledContent(member.realname, value: member.username) }
                }
                Section("卫生评分") {
                    ForEach(scores) { score in LabeledContent(score.title, value: score.value) }
                }
            }
            if let errorMessage { ContentUnavailableView("宿舍数据读取失败", systemImage: "house", description: Text(errorMessage)) }
        }
        .overlay { if isLoading { ProgressView("正在读取智慧社区…") } }
        .task { await load() }
        .refreshable { await load() }
    }

    @MainActor private func load() async {
        isLoading = true; errorMessage = nil
        do { (dormitory, members, scores) = try await OfficialCampusAPIClient.shared.fetchDormitory() }
        catch { errorMessage = error.localizedDescription }
        isLoading = false
    }
}

private struct NativeProgramView: View {
    @AppStorage("academicConnectionMode") private var connectionMode = AcademicConnectionMode.direct.rawValue
    @State private var modules: [AcademicProgramSummary] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            ForEach(modules) { module in
                VStack(alignment: .leading, spacing: 5) {
                    Text(module.title).font(.headline)
                    Text([module.requiredCredits.map { "要求 \($0.formatted()) 学分" }, module.courseCount > 0 ? "\(module.courseCount) 门计划课程" : nil].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                    if let remark = module.remark, !remark.isEmpty { Text(remark).font(.caption2).foregroundStyle(.tertiary) }
                }
            }
            if let errorMessage { ContentUnavailableView("培养方案读取失败", systemImage: "list.clipboard", description: Text(errorMessage)) }
        }
        .overlay { if isLoading { ProgressView("正在读取培养方案…") } }
        .task { await load() }
        .refreshable { await load() }
    }

    @MainActor private func load() async {
        isLoading = true; errorMessage = nil
        do {
            let mode = AcademicConnectionMode(rawValue: connectionMode) ?? .direct
            modules = try await AcademicClient(mode: mode, cookies: CampusSessionStore.shared.allCookies).fetchProgram()
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }
}

private struct NativeCampusCalendarView: View {
    @EnvironmentObject private var scheduleStore: ScheduleStore
    var body: some View {
        List {
            Section("当前学期") {
                LabeledContent("教务学期编号", value: String(AcademicPortal.currentSemesterID))
                LabeledContent("已同步课程", value: "\(Set(scheduleStore.courses.map(\.name)).count) 门")
                LabeledContent("上课安排", value: "\(scheduleStore.courses.count) 条")
            }
            ForEach(1...7, id: \.self) { weekday in
                Section(Course.weekdayNames[weekday - 1]) {
                    ForEach(scheduleStore.courses(on: weekday)) { course in
                        LabeledContent(course.name, value: "\(course.startTime)-\(course.endTime)")
                    }
                }
            }
        }
    }
}

private struct NativeCampusLifeView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var scheduleStore: ScheduleStore
    @EnvironmentObject private var studentStore: AcademicStudentStore
    @State private var weather: CampusWeather?
    @State private var weatherError: String?

    var body: some View {
        List {
            Section("实时天气") {
                if let weather {
                    HStack(spacing: 16) {
                        Image(systemName: weather.symbol).font(.largeTitle).foregroundStyle(.orange)
                        VStack(alignment: .leading) {
                            Text("\(weather.temperature, specifier: "%.1f")°").font(.title.bold())
                            Text("体感 \(weather.apparent, specifier: "%.1f")° · 湿度 \(weather.humidity)% · 风速 \(weather.wind, specifier: "%.1f") km/h")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else if let weatherError {
                    Text(weatherError).foregroundStyle(.secondary)
                } else {
                    ProgressView("正在读取 \(appState.campus.rawValue) 天气…")
                }
            }

            Section("校园生活") {
                NavigationLink {
                    TermReportView()
                        .environmentObject(scheduleStore)
                        .environmentObject(studentStore)
                } label: { Label("学期报告", systemImage: "sparkles") }
                NavigationLink { CampusMapImagesView() } label: { Label("校园地图", systemImage: "map.fill") }
                NavigationLink { CampusFloorGuideView() } label: { Label("楼层导向", systemImage: "building.2.crop.circle") }
                NavigationLink { CampusThirdPartyAppsView() } label: { Label("第三方应用", systemImage: "square.grid.2x2.fill") }
            }

            Section("校园身份") {
                LabeledContent("校区", value: appState.campus.rawValue)
                if let info = studentStore.info { LabeledContent("学生", value: "\(info.name) · \(info.department)") }
            }
        }
        .task(id: appState.campus) { await loadWeather() }
        .refreshable { await loadWeather() }
    }

    @MainActor private func loadWeather() async {
        weatherError = nil
        do {
            let coordinate = appState.campus == .hefei ? (31.77, 117.20) : (30.90, 118.71)
            var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
            components.queryItems = [
                .init(name: "latitude", value: String(coordinate.0)),
                .init(name: "longitude", value: String(coordinate.1)),
                .init(name: "current", value: "temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m"),
                .init(name: "timezone", value: "Asia/Shanghai")
            ]
            let (data, _) = try await URLSession.shared.data(from: components.url!)
            weather = try JSONDecoder().decode(CampusWeatherEnvelope.self, from: data).current
        } catch { weatherError = "天气读取失败：\(error.localizedDescription)" }
    }
}

private struct CampusWeatherEnvelope: Decodable { let current: CampusWeather }
private struct CampusWeather: Decodable {
    let temperature: Double
    let apparent: Double
    let humidity: Int
    let code: Int
    let wind: Double
    enum CodingKeys: String, CodingKey {
        case temperature = "temperature_2m"
        case apparent = "apparent_temperature"
        case humidity = "relative_humidity_2m"
        case code = "weather_code"
        case wind = "wind_speed_10m"
    }
    var symbol: String {
        switch code { case 0: "sun.max.fill"; case 1...3: "cloud.sun.fill"; case 45...48: "cloud.fog.fill"; case 51...67, 80...82: "cloud.rain.fill"; case 71...77, 85...86: "cloud.snow.fill"; default: "cloud.fill" }
    }
}

private struct CampusTermReportView: View {
    @EnvironmentObject private var scheduleStore: ScheduleStore
    @EnvironmentObject private var studentStore: AcademicStudentStore
    var body: some View {
        List {
            Section("本学期") {
                LabeledContent("课程", value: "\(Set(scheduleStore.courses.map(\.name)).count) 门")
                LabeledContent("课程安排", value: "\(scheduleStore.courses.count) 条")
                LabeledContent("上课地点", value: "\(Set(scheduleStore.courses.map(\.location).filter { !$0.isEmpty }).count) 处")
            }
            if let info = studentStore.info {
                Section("学生") {
                    LabeledContent("姓名", value: info.name)
                    LabeledContent("学院", value: info.department)
                    LabeledContent("专业", value: info.major)
                }
            }
            Section { Text("报告使用本机已同步的课表和学籍信息生成，不上传个人数据。") }
        }
        .navigationTitle("学期报告")
    }
}

private struct CampusMapView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openURL) private var openURL
    var body: some View {
        List {
            Section("校园地图") {
                Button("在地图中查看 \(appState.campus.rawValue)", systemImage: "map.fill") {
                    let name = appState.campus == .hefei ? "合肥工业大学翡翠湖校区" : "合肥工业大学宣城校区"
                    let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
                    openURL(URL(string: "https://maps.apple.com/?q=\(encoded)")!)
                }
            }
            Section { Text("可在地图应用中查看校门、教学楼、宿舍和生活服务位置并导航。") }
        }
        .navigationTitle("校园地图")
    }
}

private struct CampusFloorGuideView: View {
    struct Building: Decodable, Identifiable {
        struct Summary: Decodable { let nameZh: String; let id: Int }
        struct Floor: Decodable, Identifiable {
            let imageURL: String
            let floor: Int
            var id: String { "\(floor)|\(imageURL)" }
            enum CodingKeys: String, CodingKey { case imageURL = "image_url"; case floor }
        }
        let building: Summary
        let campus: String
        let detail: [Floor]
        var id: Int { building.id }
    }
    @State private var buildings: [Building] = []
    @State private var errorMessage: String?
    var body: some View {
        List {
            ForEach(buildings) { building in
                Section(building.building.nameZh) {
                    ForEach(building.detail.sorted { $0.floor < $1.floor }) { floor in
                        NavigationLink("\(floor.floor)F") {
                            ScrollView { AsyncImage(url: URL(string: floor.imageURL)) { image in image.resizable().scaledToFit() } placeholder: { ProgressView() } }
                                .navigationTitle("\(building.building.nameZh) \(floor.floor)F")
                        }
                    }
                }
            }
            if let errorMessage { ContentUnavailableView("楼层导向读取失败", systemImage: "building.2", description: Text(errorMessage)) }
        }
        .navigationTitle("楼层导向")
        .task { await load() }
        .refreshable { await load() }
    }
    @MainActor private func load() async {
        do {
            let url = URL(string: "https://raw.githubusercontent.com/Chiu-xaH/HFUT-Schedule/dev/src/source/building/list.json")!
            let (data, _) = try await URLSession.shared.data(from: url)
            buildings = try JSONDecoder().decode([Building].self, from: data)
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct CampusThirdPartyAppsView: View {
    @Environment(\.openURL) private var openURL
    var body: some View {
        List {
            Button("活在肥宣 · 新生指南", systemImage: "safari") { openURL(URL(string: "https://survive-hfut.cc/intro")!) }
            Button("拼多多身份码", systemImage: "shippingbox") { openURL(CampusServiceClient.pinduoduoExpressURL) }
            Button("淘宝身份码", systemImage: "shippingbox.fill") { openURL(CampusServiceClient.taobaoExpressURL) }
            Button("支付宝校园卡", systemImage: "creditcard") { openURL(CampusServiceClient.alipayCampusCardURL) }
            Link("今日校园", destination: URL(string: "https://stu.hfut.edu.cn/")!)
            Link("安徽政务服务", destination: URL(string: "https://www.ahzwfw.gov.cn/")!)
        }
        .navigationTitle("第三方应用")
    }
}

private struct NativeHolidayView: View {
    struct Notice: Identifiable {
        let title: String
        let date: String
        let url: URL
        var id: String { url.absoluteString }
    }
    @State private var notices: [Notice] = []
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        List {
            Section("调休通知") {
                ForEach(notices) { notice in
                    SourceAnchoredNavigationLink(sourceID: "holiday-notice-\(notice.id)") {
                        PortalWebView(url: notice.url)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(notice.title).font(.headline)
                            Text(notice.date).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            if notices.isEmpty, !isLoading, errorMessage == nil {
                ContentUnavailableView("暂无调休通知", systemImage: "calendar.badge.clock")
            }
            if let errorMessage { ContentUnavailableView("调休通知读取失败", systemImage: "calendar.badge.exclamationmark", description: Text(errorMessage)) }
        }
        .navigationTitle("调休通知")
        .overlay { if isLoading { ProgressView("正在搜索放假安排…") } }
        .task { await load() }
        .refreshable { await load() }
    }

    @MainActor private func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let url = URL(string: "https://news.hfut.edu.cn/zq_search.jsp?wbtreeid=1137")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let keyword = Data("放假安排".utf8).base64EncodedString()
                .addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
            request.httpBody = Data("sitenewskeycode=\(keyword)&currentnum=1".utf8)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
                  let html = String(data: data, encoding: .utf8) else {
                throw URLError(.badServerResponse)
            }
            notices = Self.parseNotices(html)
        } catch { errorMessage = error.localizedDescription }
    }

    private static func parseNotices(_ html: String) -> [Notice] {
        let blocks = matches(html, #"(?is)<li\b[^>]*>(.*?)</li>"#)
        return blocks.compactMap { block in
            guard let href = first(block, #"(?is)<a\b[^>]*href=[\"']([^\"']+)[\"']"#) else { return nil }
            let title = clean(first(block, #"(?is)<p\b[^>]*class=[\"'][^\"']*title[^\"']*[\"'][^>]*>(.*?)</p>"#) ?? first(block, #"(?is)<a\b[^>]*>(.*?)</a>"#) ?? "")
            guard !title.isEmpty else { return nil }
            let date = clean(first(block, #"(?is)<i\b[^>]*>(.*?)</i>"#) ?? "")
            let url = URL(string: href, relativeTo: URL(string: "https://news.hfut.edu.cn/")!)!.absoluteURL
            return Notice(title: title, date: date, url: url)
        }
    }

    private static func matches(_ text: String, _ pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            guard let range = Range($0.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
    }

    private static func first(_ text: String, _ pattern: String) -> String? { matches(text, pattern).first }
    private static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct NativeExpressView: View {
    @Environment(\.openURL) private var openURL
    var body: some View {
        List {
            Section("取件身份码") {
                Button("拼多多身份码", systemImage: "shippingbox.fill") { openURL(CampusServiceClient.pinduoduoExpressURL) }
                Button("淘宝身份码", systemImage: "shippingbox.circle.fill") { openURL(CampusServiceClient.taobaoExpressURL) }
            }
            Section { Text("与 Android 原版一致：拼多多用于校区快递站身份码，淘宝入口用于合肥校区取件身份码。") }
        }
    }
}

private struct ExternalLinkView: View {
    let feature: CampusFeature
    let url: URL
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 22) {
            GlassIcon(systemName: feature.systemImage, size: 72)
            Text(feature.subtitle)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Button("打开对应应用", systemImage: "arrow.up.forward.app") {
                openURL(url)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background.ignoresSafeArea())
    }
}

private struct NotificationsView: View {
    @EnvironmentObject private var scheduleStore: ScheduleStore
    @EnvironmentObject private var notificationManager: CourseNotificationManager
    @State private var message: String?

    var body: some View {
        VStack(spacing: 20) {
            GlassIcon(systemName: "bell.badge.fill", tint: .orange, size: 72)
            Text("课程提醒")
                .font(.title2.bold())
            Text("通知权限：\(notificationManager.authorizationDescription)\n已安排 \(notificationManager.pendingReminderCount) 条每周提醒")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if notificationManager.authorizationStatus == .denied {
                Text("请前往“设置 → 通知 → 聚在工大”开启通知。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Button("授权并刷新提醒", systemImage: "bell.and.waves.left.and.right") {
                    Task { await updateReminders() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background.ignoresSafeArea())
        .task { await notificationManager.refresh() }
        .alert("课程提醒", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("好") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private func updateReminders() async {
        do {
            notificationManager.isEnabled = true
            try await notificationManager.reschedule(for: scheduleStore.courses)
            message = "课程提醒已更新。"
        } catch {
            message = error.localizedDescription
        }
    }
}
