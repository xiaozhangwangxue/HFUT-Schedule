import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var scheduleStore: ScheduleStore
    @EnvironmentObject private var studentStore: AcademicStudentStore
    @State private var section = 0
    @State private var campusCardBalance = CampusServiceClient.shared.cachedCampusCardBalance
    @State private var isRefreshingCampusCardBalance = false
    @State private var tomorrowStatus: FocusTomorrowStatus = .firstClass(hour: nil)

    private let serviceColumns = [GridItem(.flexible()), GridItem(.flexible())]

    private var todayIndex: Int {
        Calendar.current.component(.weekday, from: Date()).mondayBasedWeekday
    }

    private var todayCourses: [Course] {
        FocusPlanResolver.courses(on: Date(), store: scheduleStore)
    }

    /// 调休上班日：今天按设置的日期上课。
    private var makeUpTargetText: String? {
        guard HolidayCalendarStore.shared.isMakeUpWorkDay(Date()),
              let target = SpecialWorkDayStore.shared.targetDate(for: Date()) else { return nil }
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
                    courseList
                } else {
                    LazyVGrid(columns: serviceColumns, spacing: 10) {
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
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle(dateTitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
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
        .onAppear {
            campusCardBalance = CampusServiceClient.shared.cachedCampusCardBalance
            Task { await refreshCampusCardBalance() }
        }
        .task {
            await HolidayCalendarStore.shared.refreshIfNeeded()
            tomorrowStatus = FocusPlanResolver.tomorrowStatus(store: scheduleStore)
        }
    }

    private var campusSnapshot: some View {
        LazyVGrid(columns: serviceColumns, spacing: 8) {
            SourceAnchoredNavigationLink(sourceID: "dashboard-snapshot-card") {
                FeatureDetailView(feature: feature(1))
            } label: {
                snapshotItem("一卡通", value: campusCardBalanceText, icon: "creditcard")
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
                        Image(systemName: "clock")
                            .font(.title2)
                            .foregroundStyle(.secondary)
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
                Text(value).font(.body).foregroundStyle(.primary).lineLimit(1)
                if let footnote {
                    Text(footnote).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
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
        let date = Date().formatted(.dateTime.month(.twoDigits).day(.twoDigits))
        return "\(date) 第\(currentWeek)周 \(Course.weekdayNames[todayIndex - 1])"
    }

    private func status(for course: Course) -> String {
        let now = Date().formatted(date: .omitted, time: .shortened)
        if now < course.startTime { return "未开始" }
        if now <= course.endTime { return "进行中" }
        return "已结束"
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
