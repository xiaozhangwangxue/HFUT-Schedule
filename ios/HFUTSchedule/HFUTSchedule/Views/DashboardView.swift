import SwiftUI

struct DashboardView: View {
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
                            SourceAnchoredNavigationLink(sourceID: "dashboard-service-\(feature.id)") {
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
            campusCardBalance = CampusServiceClient.shared.cachedCampusCardBalance
            electricity.activate(campus: appState.campus == .hefei ? .hefei : .xuancheng)
            Task { await refreshCampusCardBalance() }
            Task { await refreshLifeInformation() }
        }
        .onChange(of: appState.campus) { _, campus in
            electricity.activate(campus: campus == .hefei ? .hefei : .xuancheng)
            weather = nil; network = nil
            Task { await refreshLifeInformation() }
        }
        .onDisappear { electricity.deactivate() }
        .task {
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
        await refreshCampusCardBalance()
        await refreshLifeInformation()
        await refreshClock()
        refreshStatus = failed.isEmpty ? "刷新完成" : "已刷新可用数据；\(failed.joined(separator: "、"))暂未更新，请检查登录或网络。"
    }

    @MainActor
    private func refreshLifeInformation() async {
        let campus = appState.campus
        do {
            let value = try await CampusWeatherClient().fetch(location: campus == .hefei ? .hefei : .xuancheng)
            if campus == appState.campus { weather = value; weatherError = nil }
        } catch { if campus == appState.campus { weatherError = "天气暂未更新" } }
        do {
            let value = try await SchoolNetworkClient.shared.status(xuancheng: campus == .xuancheng)
            if campus == appState.campus { network = value; networkError = nil }
        } catch { if campus == appState.campus { networkError = "校园网暂不可连接" } }
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
        CampusAdaptiveGrid(minimumItemWidth: 180, spacing: 8, maximumContentWidth: 840) {
            if showsCard {
            VStack(spacing: 0) {
                SourceAnchoredNavigationLink(sourceID: "dashboard-snapshot-card") {
                    FeatureDetailView(feature: feature(1))
                } label: {
                    snapshotItem("一卡通", value: campusCardBalanceText, icon: "creditcard")
                }
                if let action = FocusCardAction(rawValue: cardAction), action != .none {
                    if action == .recharge {
                        Button("充值", systemImage: "plus.circle") {
                            openURL(CampusServiceClient.alipayCampusCardURL) { accepted in
                                if !accepted { openURL(CampusServiceClient.alipayCampusCardFallbackURL) }
                            }
                        }.buttonStyle(.bordered)
                    } else {
                        AppNavigationLink {
                            FocusPayCodeView()
                        } label: { Label("付款码", systemImage: "qrcode") }.buttonStyle(.bordered)
                    }
                }
            }
            }
            if showsElectric {
            SourceAnchoredNavigationLink(sourceID: "dashboard-snapshot-electricity") {
                FeatureDetailView(feature: feature(3))
            } label: {
                snapshotItem("宿舍电费", value: electricitySummary, icon: "bolt")
            }
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
            if showsWeather {
                SourceAnchoredNavigationLink(sourceID: "dashboard-weather") {
                    FeatureDetailView(feature: feature(28))
                } label: {
                    snapshotItem("天气", value: weather.map { String(format: "%.0f° · %@", $0.observation.temperature, $0.observation.condition) } ?? weatherError ?? "正在读取",
                        icon: weather?.observation.symbol ?? "cloud", footnote: weatherWarningSummary)
                }
            }
            if recordsStore.newGradeCount > 0 {
                SourceAnchoredNavigationLink(sourceID: "dashboard-new-grades") {
                    AcademicRecordsView(kind: .grades)
                } label: { snapshotItem("新出成绩", value: "\(recordsStore.newGradeCount) 门", icon: "graduationcap") }
            }
        }
        .padding(10)
        .adaptiveGlass(cornerRadius: 22, tint: AppTheme.accent.opacity(0.035))
    }

    private var weatherWarningSummary: String? {
        guard let weather else { return nil }
        switch weather.warnings {
        case .available(let items): return items.first?.title ?? "暂无预警"
        case .unavailable: return "预警暂未更新"
        }
    }

    private var electricitySummary: String {
        guard !electricity.results.isEmpty else { return "设置默认宿舍" }
        return electricity.results.map { item in
            if item.isLoading { return "\(item.title)：读取中" }
            if item.error != nil { return "\(item.title)：暂未更新" }
            let balance = item.values.first { $0.key.contains("余额") || $0.key.contains("剩余") || $0.key.contains("金额") }?.value
                ?? item.values.sorted { $0.key < $1.key }.first?.value ?? "未配置"
            return "\(item.title)：\(balance)"
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
              CampusServiceClient.shared.savedHuiXinToken != nil else { return }
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
