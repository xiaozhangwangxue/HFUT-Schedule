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

    private var todayIndex: Int {
        Calendar.current.component(.weekday, from: now).mondayBasedWeekday
    }

    private var todayCourses: [Course] {
        FocusPlanResolver.courses(on: now, store: scheduleStore)
            .filter { showFinished || Self.minutes($0.endTime) >= Self.minutesOfDay(now) }
    }

    /// 调休上班日：今天按设置的日期上课。
    private var makeUpTargetText: String? {
        guard HolidayCalendarStore.shared.isMakeUpWorkDay(now),
              let target = SpecialWorkDayStore.shared.targetDate(for: now) else { return nil }
        return "调休：今天按 \(FocusTomorrowStatus.shortDate(target)) 的课表上课"
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
                    examList
                    courseList
                    eventList
                } else {
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
        .navigationTitle(dateTitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink { CustomEventsView() } label: { Image(systemName: "calendar.badge.plus") }
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
            Task { await refreshCampusCardBalance() }
        }
        .task {
            await HolidayCalendarStore.shared.refreshIfNeeded()
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
                    if !event.location.isEmpty { Text(event.location).font(.caption).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(16).adaptiveGlass(cornerRadius: 20)
            }.buttonStyle(.plain)
        }
    }

    private var campusSnapshot: some View {
        CampusAdaptiveGrid(minimumItemWidth: 180, spacing: 8, maximumContentWidth: 840) {
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
                        NavigationLink {
                            FocusPayCodeView()
                        } label: { Label("付款码", systemImage: "qrcode") }.buttonStyle(.bordered)
                    }
                }
            }
            SourceAnchoredNavigationLink(sourceID: "dashboard-snapshot-electricity") {
                FeatureDetailView(feature: feature(3))
            } label: {
                snapshotItem("宿舍电费", value: "点击查询", icon: "bolt")
            }
            SourceAnchoredNavigationLink(sourceID: "dashboard-tomorrow") {
                TomorrowPlanView()
            } label: {
                snapshotItem(tomorrowStatus.title, value: tomorrowStatus.value, icon: tomorrowStatus.symbol, footnote: tomorrowStatus.detail)
            }
            .buttonStyle(.plain)
            SourceAnchoredNavigationLink(sourceID: "dashboard-snapshot-network") {
                FeatureDetailView(feature: feature(4))
            } label: {
                snapshotItem("校园网", value: "查看状态", icon: "globe")
            }
        }
        .padding(10)
        .adaptiveGlass(cornerRadius: 22, tint: AppTheme.accent.opacity(0.035))
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
            ContentUnavailableView("今天没有课程", systemImage: "calendar.badge.checkmark")
                .frame(minHeight: 180)
                .adaptiveGlass(cornerRadius: 22)
        } else {
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
        switch courseState(course) {
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
