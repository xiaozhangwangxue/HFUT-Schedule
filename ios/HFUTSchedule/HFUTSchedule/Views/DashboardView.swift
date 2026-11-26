import SwiftUI

struct DashboardView: View {
    private let isUIPreview: Bool
    @MainActor init() {
        #if DEBUG
        isUIPreview = AppUIPreview.enabled
        if isUIPreview {
            _weather = State(initialValue: AppUIPreview.weather)
            _campusCardBalance = State(initialValue: 128.50)
            _networkError = State(initialValue: "余额 ¥20.00（示例）")
            _electricity = StateObject(wrappedValue: AppUIPreview.electricityModel())
            _bathingBalance = StateObject(wrappedValue: AppUIPreview.phoneModel(.bathing))
            _laundryBalance = StateObject(wrappedValue: AppUIPreview.phoneModel(.laundry))
        }
        #else
        isUIPreview = false
        #endif
    }
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var scheduleStore: ScheduleStore
    @EnvironmentObject private var eventStore: CustomEventStore
    @EnvironmentObject private var recordsStore: AcademicRecordsStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @AppStorage(AppSettingsKey.focusCardAction) private var cardAction = FocusCardAction.recharge.rawValue
    @AppStorage(AppSettingsKey.showFinishedToday) private var showFinished = true
    @AppStorage(AppSettingsKey.showExpiredEvents) private var showExpired = false
    @State private var now = Date()
    @State private var editingEvent: CustomEvent?
    @State private var quickActionError: String?
    @EnvironmentObject private var studentStore: AcademicStudentStore
    @State private var section = 0
    @AppStorage("bathingPhone") private var bathingPhone = ""
    @AppStorage("laundryPhone") private var laundryPhone = ""
    @StateObject private var bathingBalance = PhoneFeeBalanceModel(service: .bathing)
    @StateObject private var laundryBalance = PhoneFeeBalanceModel(service: .laundry)
    @State private var lastLifeRefresh: Date?
    @State private var lifeRefreshing = false
    @State private var lastCardRefresh: Date?
    @State private var campusCardBalance = CampusServiceClient.shared.cachedCampusCardBalance
    @State private var isRefreshingCampusCardBalance = false
    @State private var tomorrowStatus: FocusTomorrowStatus = .firstClass(hour: nil)
    @StateObject private var electricity = ElectricityQueryModel()
    @State private var publicEvents: [PublicCampusEvent] = []
    @State private var refreshing = false
    @State private var refreshStatus: String?
    @State private var weather: CampusWeatherReport?
    @State private var weatherError: String?
    @State private var network: SchoolNetworkStatus?
    @State private var networkError: String?
    @AppStorage("focusShowsCard") private var showsCard = true
    @AppStorage("focusShowsElectric") private var showsElectric = true
    @AppStorage("focusShowsNetwork") private var showsNetwork = true
    @AppStorage("focusShowsTomorrow") private var showsTomorrowCard = true
    @AppStorage("focusShowsWeather") private var showsWeather = true

    private var todayIndex: Int {
        Calendar.current.component(.weekday, from: now).mondayBasedWeekday
    }

    private var todayCourses: [Course] {
        FocusPlanResolver.courses(on: displayedCourseDate, store: scheduleStore)
            .filter { showsTomorrow || showFinished || Self.minutes($0.endTime) >= Self.minutesOfDay(now) }
    }

    private var showsTomorrow: Bool {
        FocusPlanResolver.showsTomorrow(today: FocusPlanResolver.courses(on: now, store: scheduleStore), now: now)
    }

    private var displayedCourseDate: Date { showsTomorrow ? FocusPlanResolver.tomorrow(from: now) : now }

    /// 调休上班日：今天按设置的日期上课。
    private var makeUpTargetText: String? {
        guard HolidayCalendarStore.shared.isMakeUpWorkDay(displayedCourseDate),
              let target = SpecialWorkDayStore.shared.targetDate(for: displayedCourseDate) else { return nil }
        return "调休：\(showsTomorrow ? "明天" : "今天")按 \(FocusTomorrowStatus.shortDate(target)) 的课表上课"
    }

    private var currentWeek: Int {
        ScheduleCalendar.currentWeek(termStart: ScheduleCalendar.termStart(from: scheduleStore.courses))
    }

    private var quickFeatures: [CampusFeature] {
        [1, 3, 4, 6, 7, 15, 19, 24].compactMap { id in
            FeatureCatalog.all.first { $0.id == id }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if isUIPreview { Text("界面预览 · 示例数据").font(.caption).foregroundStyle(.secondary) }
                Picker("聚焦内容", selection: $section) {
                    Text("重要安排").tag(0)
                    Text("其他事项").tag(1)
                }
                .pickerStyle(.segmented)

                if section == 0 {
                    campusSnapshot
                    weatherWarnings
                    publicEventList
                    examList
                    courseList
                    eventList
                } else {
                    publicEventList
                    eventList
                    CampusAdaptiveGrid(minimumItemWidth: 180, spacing: 10, maximumContentWidth: 840) {
                        ForEach(quickFeatures) { feature in
                            SourceAnchoredNavigationLink(sourceID: "dashboard-service-\(feature.id)", title: feature.title) {
                                FeatureDetailView(feature: feature)
                            } label: {
                                focusService(feature)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxWidth: 840)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .refreshable { await refreshAll() }
        .safeAreaInset(edge: .bottom) {
            if let refreshStatus { Text(refreshStatus).font(.caption).foregroundStyle(.secondary).padding(8).background(.regularMaterial) }
        }
        .navigationTitle(dateTitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                AppNavigationLink { CustomEventsView() } label: { Image(systemName: "calendar.badge.plus") }
                    .accessibilityLabel("自建日程")
                SourceAnchoredNavigationLink(sourceID: "dashboard-toolbar-cloud") {
                    FeatureDetailView(feature: feature(39))
                } label: {
                    Image(systemName: "icloud")
                }
                SourceAnchoredNavigationLink(sourceID: "dashboard-toolbar-notifications") {
                    FeatureDetailView(feature: feature(15))
                } label: {
                    Image(systemName: "bell")
                }
                SourceAnchoredNavigationLink(sourceID: "dashboard-toolbar-login") {
                    FeatureDetailView(feature: feature(42))
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .sheet(item: $editingEvent) { CustomEventEditor(event: $0) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshClock() } }
        }
        .onAppear {
            if isUIPreview { electricity.activateIfNeeded(campus: .hefei); return }
            campusCardBalance = CampusServiceClient.shared.cachedCampusCardBalance
            electricity.activateIfNeeded(campus: appState.campus == .hefei ? .hefei : .xuancheng)
            Task { await refreshCampusCardBalance() }
            Task { await refreshLifeInformation() }
        }
        .onChange(of: appState.campus) { _, campus in
            if isUIPreview { return }
            electricity.activate(campus: campus == .hefei ? .hefei : .xuancheng)
            weather = nil; network = nil; lastLifeRefresh = nil
            Task { await refreshLifeInformation() }
        }
        .task(id: "\(appState.campus.rawValue)|\(StudentPhone.from(studentStore.info) ?? "")|\(bathingPhone)|\(laundryPhone)") { await refreshPhoneBalances() }
        .task {
            if isUIPreview { await refreshClock(); return }
            await HolidayCalendarStore.shared.refreshIfNeeded()
            await CampusCloudConfigStore.shared.refreshIfNeeded()
            publicEvents = CampusCloudConfigStore.shared.publicEvents
            await refreshClock()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { break }
                await refreshClock()
            }
        }
    }

    @MainActor
    private func refreshClock() async {
        now = Date()
        tomorrowStatus = FocusPlanResolver.tomorrowStatus(store: scheduleStore)
    }

    @MainActor
    private func refreshAll() async {
        if isUIPreview { await refreshPhoneBalances(force: true); return }
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        var failed: [String] = []
        refreshStatus = "正在刷新课表与校园信息…"
        do { _ = try await CampusServiceClient.shared.refreshOnePortalToken() } catch { failed.append("登录状态") }
        await CampusCloudConfigStore.shared.refreshIfNeeded(force: true)
        await HolidayCalendarStore.shared.refreshIfNeeded(force: true)
        publicEvents = CampusCloudConfigStore.shared.publicEvents
        let source = ScheduleSource(rawValue: UserDefaults.standard.string(forKey: AppSettingsKey.defaultCourseSource) ?? "academic") ?? .academic
        await ScheduleSourceCoordinator.shared.refresh(source, store: scheduleStore)
        let mode = AcademicConnectionMode(rawValue: UserDefaults.standard.string(forKey: "academicConnectionMode") ?? "direct") ?? .direct
        let client = AcademicClient(mode: mode, cookies: CampusSessionStore.shared.allCookies)
        do { recordsStore.replaceGrades(with: try await client.fetchGrades()) } catch { failed.append("成绩") }
        do { recordsStore.replaceExams(with: try await client.fetchExams()) } catch { failed.append("考试") }
        do { studentStore.replace(with: try await client.fetchStudentInfo()) } catch { failed.append("学籍") }
        electricity.refreshSaved()
        lastCardRefresh = nil; lastLifeRefresh = nil
        await refreshCampusCardBalance()
        await refreshLifeInformation()
        await refreshPhoneBalances(force: true)
        await refreshClock()
        refreshStatus = failed.isEmpty ? "刷新完成" : "已刷新可用数据；\(failed.joined(separator: "、"))暂未更新，请检查登录或网络。"
    }

    @MainActor
    private func refreshLifeInformation() async {
        guard !lifeRefreshing, lastLifeRefresh.map({ Date().timeIntervalSince($0) >= 60 }) != false else { return }
        lifeRefreshing = true
        defer { lifeRefreshing = false }
        let campus = appState.campus
        lastLifeRefresh = Date()
        async let weatherResult = captureResult { try await CampusWeatherClient().fetch(location: campus == .hefei ? .hefei : .xuancheng) }
        async let networkResult = captureResult { try await SchoolNetworkClient.shared.status(xuancheng: campus == .xuancheng) }
        do {
            let value = try await weatherResult.get()
            if campus == appState.campus { weather = value; weatherError = nil }
        } catch { if campus == appState.campus { weatherError = "天气暂未更新" } }
        do {
            let value = try await networkResult.get()
            if campus == appState.campus { network = value; networkError = nil }
        } catch { if campus == appState.campus { networkError = "校园网暂不可连接" } }
    }

    private func captureResult<T>(_ operation: () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await operation()) } catch { return .failure(error) }
    }

    @MainActor private func refreshPhoneBalances(force: Bool = false) async {
        #if DEBUG
        if isUIPreview {
            await bathingBalance.refresh(campus: .hefei, phone: AppUIPreview.phone, force: force)
            await laundryBalance.refresh(campus: .hefei, phone: AppUIPreview.phone, force: force)
            return
        }
        #endif
        if StudentPhone.from(studentStore.info) == nil { await studentStore.refresh() }
        guard !Task.isCancelled else { return }
        let profilePhone = await studentStore.phoneForLifeServices()
        guard !Task.isCancelled else { return }
        let bathPhone = profilePhone ?? bathingPhone
        let washPhone = profilePhone ?? StudentPhone.normalized(laundryPhone) ?? bathingPhone
        async let bath: Void = bathingBalance.refresh(campus: appState.campus, phone: bathPhone, force: force)
        async let laundry: Void = laundryBalance.refresh(campus: appState.campus, phone: washPhone, force: force)
        _ = await (bath, laundry)
    }

    @ViewBuilder
    private var weatherWarnings: some View {
        if showsWeather, let weather, case .available(let warnings) = weather.warnings {
            ForEach(warnings) { item in
                VStack(alignment: .leading, spacing: 7) {
                    Label(item.title, systemImage: "exclamationmark.triangle.fill").font(.headline).foregroundStyle(.orange)
                    Text(item.text).font(.subheadline)
                    AppNavigationLink("官方预警详情") { PortalWebView(url: weather.warningURL) }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).adaptiveGlass(cornerRadius: 20)
            }
        }
    }

    @ViewBuilder
    private var publicEventList: some View {
        ForEach(publicEvents.filter { ($0.end >= now || showExpired) && $0.isImportant(at: now) == (section == 0) }) { event in
            VStack(alignment: .leading, spacing: 8) {
                Label(event.title, systemImage: event.isDeadline ? "hourglass" : "calendar").font(.headline)
                Text(event.time.isEmpty ? event.end.formatted(date: .abbreviated, time: .shortened) : event.time)
                    .font(.caption).foregroundStyle(.secondary)
                Text(event.detail).font(.subheadline).textSelection(.enabled)
                HStack {
                    if let url = LearningPlatform.url(for: event.detail) {
                        Button("打开学习平台", systemImage: "arrow.up.right.square") {
                            openURL(url) { opened in
                                if !opened, let fallback = LearningPlatform.fallback(for: event.detail) { openURL(fallback) }
                            }
                        }
                    }
                    SingleCalendarExportButton(occurrence: PlatformScheduleOccurrence(id: "public|\(event.id)",
                        sourceID: ScheduleSourceParser.stableID(event.id).uuidString,
                        kind: event.isDeadline ? .deadline : .event, title: event.title, location: "", detail: event.detail,
                        start: event.start, end: event.end))
                }.font(.caption)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(16).adaptiveGlass(cornerRadius: 20)
        }
    }

    @ViewBuilder
    private var examList: some View {
        ForEach(UpcomingExamResolver.focusExams(recordsStore.exams, now: now, calendar: ScheduleCalendar.calendar)) { item in
            SourceAnchoredNavigationLink(sourceID: "focus-exam-\(item.id.uuidString)") {
                UpcomingExamDetailView(item: item)
            } label: {
                VStack(alignment: .leading, spacing: 7) {
                    Label("考试 · \(item.exam.name)", systemImage: "pencil.and.list.clipboard")
                        .font(.headline).foregroundStyle(.primary)
                    Text(item.exam.dateTime).font(.subheadline).foregroundStyle(.secondary)
                    Label(item.location, systemImage: "mappin.and.ellipse").font(.subheadline).foregroundStyle(.secondary)
                    Text(examCountdown(item)).font(.caption.weight(.semibold)).foregroundStyle(.red)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                .adaptiveGlass(cornerRadius: 22, tint: .red.opacity(0.08), interactive: true)
            }.buttonStyle(.plain)
        }
    }

    private func examCountdown(_ item: ResolvedAcademicExam) -> String {
        if now >= item.start { return "考试进行中" }
        let days = ScheduleCalendar.calendar.dateComponents([.day], from: ScheduleCalendar.calendar.startOfDay(for: now),
            to: ScheduleCalendar.calendar.startOfDay(for: item.start)).day ?? 0
        if days == 0 { return "今天考试" }
        if days == 1 { return "明天考试" }
        return "\(days) 天后考试"
    }

    @ViewBuilder
    private var eventList: some View {
        if section == 0, BirthdayGreeting.isBirthday(fields: studentStore.info?.fields ?? [:], on: now) {
            Label("生日快乐！愿新的一岁学有所获，生活顺心。", systemImage: "birthday.cake")
                .font(.subheadline).padding(16).adaptiveGlass(cornerRadius: 20)
        }
        if let error = eventStore.storageError { Text(error).font(.footnote).foregroundStyle(.red) }
        ForEach(eventStore.events.filter {
            $0.appears(on: now, showExpired: showExpired) && ($0.isImportant(on: now) == (section == 0))
        }.sorted { $0.end < $1.end }) { event in
            Button { editingEvent = event } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Label(event.title, systemImage: event.kind == .deadline ? "hourglass" : "calendar")
                    Text(event.end.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    if event.kind == .deadline { Text(event.countdown(at: now)).font(.caption.weight(.semibold)).foregroundStyle(.orange) }
                    if ScheduleCalendar.calendar.isDate(event.kind == .deadline ? event.end : event.start,
                        inSameDayAs: FocusPlanResolver.tomorrow(from: now)) { Text("明天").font(.caption.weight(.semibold)) }
                    if !event.location.isEmpty { Text(event.location).font(.caption).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(16).adaptiveGlass(cornerRadius: 20)
            }.buttonStyle(.plain)
        }
    }

    private var campusSnapshot: some View {
        VStack(spacing: 10) {
        CampusAdaptiveGrid(minimumItemWidth: 180, spacing: 8, maximumContentWidth: 840) {
            if showsCard {
                focusBalanceTile("一卡通", value: campusCardBalanceText, icon: "creditcard", destination: { FeatureDetailView(feature: feature(1)) }) {
                    if let action = FocusCardAction(rawValue: cardAction), action != .none {
                        if action == .recharge {
                            Button {
                                openURL(CampusServiceClient.alipayCampusCardURL) { accepted in
                                    if !accepted { openURL(CampusServiceClient.alipayCampusCardFallbackURL) }
                                }
                            } label: { rechargePlusIcon }
                            .buttonStyle(.plain).accessibilityLabel("校园卡充值")
                        } else {
                            AppNavigationLink { FocusPayCodeView() } label: {
                                Image(systemName: "qrcode").font(.body.weight(.semibold)).frame(width: 44, height: 44)
                            }.buttonStyle(.plain).accessibilityLabel("校园卡付款码")
                        }
                    }
                }
            }
            if showsElectric {
                balanceSnapshot("宿舍电费", value: electricitySummary, icon: "bolt", chargeItemID: appState.campus == .hefei ? 1 : 261) { ElectricityServiceView() }
            }
            balanceSnapshot("洗澡余额", value: bathingBalance.summary, icon: "shower", footnote: bathingBalance.error, chargeItemID: appState.campus == .hefei ? 222 : 223) { BathingServiceView() }
            if appState.campus == .hefei {
                balanceSnapshot("洗衣余额", value: laundryBalance.summary, icon: "washer", footnote: laundryBalance.error, chargeItemID: 26) { LaundryServiceView() }
            }
            if showsTomorrowCard {
            SourceAnchoredNavigationLink(sourceID: "dashboard-tomorrow") {
                TomorrowPlanView()
            } label: {
                snapshotItem(tomorrowStatus.title, value: tomorrowStatus.value, icon: tomorrowStatus.symbol, footnote: tomorrowStatus.detail)
            }
            .buttonStyle(.plain)
            }
            if showsNetwork {
            SourceAnchoredNavigationLink(sourceID: "dashboard-snapshot-network") {
                FeatureDetailView(feature: feature(4))
            } label: {
                snapshotItem("校园网", value: network.map { String(format: "余额 ¥%.2f", $0.fee) } ?? networkError ?? "正在读取",
                    icon: "globe", footnote: network.map { String(format: "已用 %.2f GB", $0.usedMB / 1024) })
            }
            }
            if recordsStore.newGradeCount > 0 {
                SourceAnchoredNavigationLink(sourceID: "dashboard-new-grades") {
                    AcademicRecordsView(kind: .grades)
                } label: { snapshotItem("新出成绩", value: "\(recordsStore.newGradeCount) 门", icon: "graduationcap") }
            }
        }
        if showsWeather { focusWeatherBar }
        }
        .padding(10)
        .adaptiveGlass(cornerRadius: 22, tint: AppTheme.accent.opacity(0.035))
    }

    private var electricitySummary: String {
        guard !electricity.results.isEmpty else { return "设置默认宿舍" }
        return electricity.results.map { item in
            if item.isLoading { return "\(item.title)：读取中" }
            if item.error != nil { return "\(item.title)：暂未更新" }
            let balance = item.values.first { $0.key.contains("余额") || $0.key.contains("剩余") || $0.key.contains("金额") }?.value
                ?? item.values.sorted { $0.key < $1.key }.first?.value ?? "未配置"
            let title = item.title.replacingOccurrences(of: "电费", with: "")
            return "\(title)：\(balance)"
        }.joined(separator: "\n")
    }

    @ViewBuilder
    private var courseList: some View {
        if let makeUpTargetText {
            Text(makeUpTargetText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
        if todayCourses.isEmpty {
            ContentUnavailableView(showsTomorrow ? "明天没有课程" : "今天没有课程", systemImage: "calendar.badge.checkmark")
                .frame(minHeight: 180)
                .adaptiveGlass(cornerRadius: 22)
        } else {
            Text(showsTomorrow ? "明天的课程" : "今天的课程")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(todayCourses) { course in
                SourceAnchoredNavigationLink(sourceID: "dashboard-course-\(course.id.uuidString)") {
                    CourseDetailView(course: course)
                } label: {
                    HStack(alignment: .top, spacing: 14) {
                        courseIcon(for: course)
                            .frame(width: 34)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(course.startTime)-\(course.endTime)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text(course.name).font(.title3.weight(.medium)).foregroundStyle(.primary)
                            if let place = course.location.nonEmpty {
                                Text(place).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(status(for: course))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .adaptiveGlass(cornerRadius: 22, tint: AppTheme.accent.opacity(0.025), interactive: true)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var rechargePlusIcon: some View {
        Image(systemName: "plus").font(.body.weight(.semibold)).frame(width: 44, height: 44).contentShape(Rectangle())
    }

    private func balanceSnapshot<Destination: View>(_ title: String, value: String, icon: String, footnote: String? = nil, chargeItemID: Int, @ViewBuilder destination: @escaping () -> Destination) -> some View {
        focusBalanceTile(title, value: value, icon: icon, footnote: footnote, destination: destination) {
            AppNavigationLink(title: title + "充值") { HuiXinFeeChargeView(itemID: chargeItemID, title: title + "充值") } label: { rechargePlusIcon }
                .buttonStyle(.plain).accessibilityLabel(title + "充值")
        }
    }

    private func focusBalanceTile<Destination: View, Action: View>(_ title: String, value: String, icon: String, footnote: String? = nil, @ViewBuilder destination: @escaping () -> Destination, @ViewBuilder action: () -> Action) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.title3.weight(.medium)).foregroundStyle(.secondary).frame(width: 28)
                AppNavigationLink(title: title, destination: destination) {
                    Text(title).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain)
                action()
            }
            AppNavigationLink(title: title, destination: destination) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(value).font(.body).foregroundStyle(.primary).lineLimit(4)
                    if let footnote { Text(footnote).font(.caption2).foregroundStyle(.tertiary).lineLimit(2) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 40).padding(.bottom, 6)
            }.buttonStyle(.plain)
        }.frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
    }

    private var focusWeatherBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            SourceAnchoredNavigationLink(sourceID: "dashboard-weather", title: "天气") { FeatureDetailView(feature: feature(28)) } label: {
                HStack(alignment: .top, spacing: 12) {
                    focusWeatherDay("今天", value: weather.map { String(format: "%.0f° · %@", $0.observation.temperature, $0.observation.condition) } ?? weatherError ?? "正在读取",
                        symbol: weather?.observation.symbol ?? "cloud", range: weather?.temperatureRange)
                    focusWeatherDay("明天", value: weather?.tomorrowForecast?.condition ?? (weather == nil && weatherError == nil ? "正在读取" : "预报暂未更新"),
                        symbol: weather?.tomorrowForecast?.symbol ?? "cloud", range: weather?.tomorrowForecast?.temperatureRange)
                }.frame(maxWidth: .infinity, minHeight: 68, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if let weather, case .available(let warnings) = weather.warnings {
                ForEach(warnings) { warning in
                    Link(destination: weather.warningURL) {
                        Label(warning.title, systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func focusWeatherDay(_ day: String, value: String, symbol: String, range: CampusWeatherTemperatureRange?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.title2).foregroundStyle(.secondary).frame(width: 28)
                Text(day).font(.caption).foregroundStyle(.secondary)
            }
            Text(value).font(.body).foregroundStyle(.primary).lineLimit(2)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { focusWeatherTemperatures(range) }
                VStack(alignment: .leading, spacing: 2) { focusWeatherTemperatures(range) }
            }.font(.subheadline.monospacedDigit())
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func focusWeatherTemperatures(_ range: CampusWeatherTemperatureRange?) -> some View {
        Text("最高 \(range.map { String(format: "%.0f°", $0.maximum) } ?? "—")").foregroundStyle(.orange).fixedSize()
        Text("最低 \(range.map { String(format: "%.0f°", $0.minimum) } ?? "—")").foregroundStyle(.secondary).fixedSize()
    }

    private func snapshotItem(_ title: String, value: String, icon: String, footnote: String? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.body).foregroundStyle(.primary).lineLimit(2)
                if let footnote {
                    Text(footnote).font(.caption2).foregroundStyle(.tertiary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func focusService(_ feature: CampusFeature) -> some View {
        HStack(spacing: 10) {
            Image(systemName: feature.systemImage).foregroundStyle(.secondary).frame(width: 24)
            Text(feature.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 58)
        .adaptiveGlass(cornerRadius: 14, interactive: true)
    }

    private var dateTitle: String {
        let date = now.formatted(.dateTime.month(.twoDigits).day(.twoDigits))
        return "\(date) 第\(currentWeek)周 \(Course.weekdayNames[todayIndex - 1])"
    }

    private func status(for course: Course) -> String {
        if showsTomorrow { return "明天" }
        return switch courseState(course) {
        case .notStarted: "未开始"
        case .ongoing: "上课中"
        case .ended: "已下课"
        }
    }

    private enum CourseState { case notStarted, ongoing, ended }

    @ViewBuilder
    private func courseIcon(for course: Course) -> some View {
        switch courseState(course) {
        case .ongoing:
            CircularProgressIcon(progress: courseProgress(course), tint: AppTheme.accent)
        case .notStarted:
            Image(systemName: "calendar")
                .font(.title2)
                .foregroundStyle(.secondary)
        case .ended:
            Image(systemName: "checkmark.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }

    private func courseState(_ course: Course) -> CourseState {
        if showsTomorrow { return .notStarted }
        let now = Self.minutesOfDay(self.now)
        let start = Self.minutes(course.startTime)
        let end = Self.minutes(course.endTime)
        if now < start { return .notStarted }
        if now <= end { return .ongoing }
        return .ended
    }

    /// 当前课程已进行的比例，用于环形进度图标（对应上游 CourseProgressIcon）。
    private func courseProgress(_ course: Course) -> Double {
        let now = Self.minutesOfDay(self.now)
        let start = Self.minutes(course.startTime)
        let end = Self.minutes(course.endTime)
        guard end > start else { return 0 }
        return min(1, max(0, (now - start) / (end - start)))
    }

    private static func minutes(_ value: String) -> Double {
        let parts = value.split(separator: ":").compactMap { Double($0) }
        guard let hour = parts.first else { return 0 }
        return hour * 60 + (parts.count > 1 ? parts[1] : 0)
    }

    private static func minutesOfDay(_ date: Date) -> Double {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Double(components.hour ?? 0) * 60 + Double(components.minute ?? 0)
    }

    private var campusCardBalanceText: String {
        if let campusCardBalance {
            return String(format: "¥ %.2f", campusCardBalance)
        }
        if isRefreshingCampusCardBalance { return "正在读取" }
        return CampusServiceClient.shared.savedHuiXinToken == nil ? "登录后同步" : "暂无余额"
    }

    @MainActor
    private func refreshCampusCardBalance() async {
        guard !isRefreshingCampusCardBalance,
              lastCardRefresh.map({ Date().timeIntervalSince($0) >= 60 }) != false,
              CampusServiceClient.shared.savedHuiXinToken != nil else { return }
        lastCardRefresh = Date()
        isRefreshingCampusCardBalance = true
        defer { isRefreshingCampusCardBalance = false }
        do {
            let cards = try await CampusServiceClient.shared.fetchCampusCards()
            if let card = cards.first {
                campusCardBalance = card.balance + card.unsettledAmount
            }
        } catch {
            // A transient refresh failure must not erase the last known balance.
            campusCardBalance = CampusServiceClient.shared.cachedCampusCardBalance
        }
    }

    private func feature(_ id: Int) -> CampusFeature {
        FeatureCatalog.all.first { $0.id == id } ?? FeatureCatalog.all[0]
    }
}

private extension Int {
    var mondayBasedWeekday: Int { self == 1 ? 7 : self - 1 }
}

private extension String {
    var nonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
