import SwiftUI

/// 聚焦页「明天」卡片的四种状态，对应 Android 版 FocusItems.TodayUI。
enum FocusTomorrowStatus: Equatable {
    /// 明天是法定节假日（或周末）休息
    case holiday(name: String)
    /// 明天是调休上班日，按 targetDate 的课表上课
    case makeUpWorkDay(targetDate: String?)
    /// 明天正常上课，hour 为第一节课所在小时；nil 表示无课
    case firstClass(hour: Int?)

    var title: String { "明天" }

    var value: String {
        switch self {
        case .holiday(let name):
            name.isEmpty ? "节假日休息" : "\(name)休息"
        case .makeUpWorkDay:
            "调休非休息"
        case .firstClass(let hour):
            switch hour {
            case nil: "无课"
            case 8: "有早八"
            case 9: "有早九"
            case 10, 11: "有早十"
            default: "未知"
            }
        }
    }

    var detail: String? {
        switch self {
        case .holiday:
            nil
        case .makeUpWorkDay(let target):
            target.map { "上 \(Self.shortDate($0)) 的课" } ?? "点击设置补课日期"
        case .firstClass:
            nil
        }
    }

    var symbol: String {
        switch self {
        case .holiday: "sparkles"
        case .makeUpWorkDay: "briefcase.fill"
        case .firstClass(let hour):
            switch hour {
            case nil: "checkmark.circle.fill"
            case 8, 9: "sunrise.fill"
            case 10, 11: "sun.max.fill"
            case .some(let other) where other >= 14: "moon.zzz.fill"
            default: "questionmark.circle"
            }
        }
    }

    static func shortDate(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 3 else { return key }
        let weekday = FocusPlanResolver.weekdayName(forDateKey: key).map { "（\($0)）" } ?? ""
        return "\(parts[1])-\(parts[2])\(weekday)"
    }
}

/// 计算今天 / 明天的课程与状态（含调休补课映射）。
enum FocusPlanResolver {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = .current
        calendar.firstWeekday = 2
        return calendar
    }()

    static func tomorrow(from date: Date = Date()) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
    }

    static func weekdayName(forDateKey key: String) -> String? {
        guard let date = date(fromKey: key) else { return nil }
        return weekdayName(for: date)
    }

    static func weekdayName(for date: Date) -> String {
        let index = weekday(for: date)
        return Course.weekdayNames[max(0, min(6, index - 1))]
    }

    /// 周一 = 1 ... 周日 = 7
    static func weekday(for date: Date) -> Int {
        let component = calendar.component(.weekday, from: date)
        return component == 1 ? 7 : component - 1
    }

    static func date(fromKey key: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: key)
    }

    /// 调休日按设置的日期上课。
    static func effectiveDate(for date: Date) -> Date {
        if HolidayCalendarStore.shared.isMakeUpWorkDay(date),
           let target = SpecialWorkDayStore.shared.targetDate(for: date),
           let parsed = Self.date(fromKey: target) {
            return parsed
        }
        return date
    }

    @MainActor
    static func courses(on date: Date, store: ScheduleStore) -> [Course] {
        let effective = effectiveDate(for: date)
        let weekday = self.weekday(for: effective)
        let termStart = ScheduleCalendar.termStart(from: store.courses)
        let week = weekNumber(for: effective, termStart: termStart)
        return store.courses
            .filter { $0.weekday == weekday }
            .filter { course in
                guard let weeks = course.weekIndices, !weeks.isEmpty else { return true }
                return weeks.contains(week)
            }
            .sorted { $0.startTime < $1.startTime }
    }

    static func weekNumber(for date: Date, termStart: Date?) -> Int {
        guard let termStart else { return 1 }
        let days = calendar.dateComponents([.day], from: termStart, to: calendar.startOfDay(for: date)).day ?? 0
        guard days >= 0 else { return 1 }
        return min(20, max(1, days / 7 + 1))
    }

    @MainActor
    static func firstCourseHour(on date: Date, store: ScheduleStore) -> Int? {
        guard let first = courses(on: date, store: store).first else { return nil }
        return Int(first.startTime.split(separator: ":").first ?? "")
    }

    /// 明天状态：休息 / 调休 / 早八早九早十 / 无课。
    @MainActor
    static func tomorrowStatus(store: ScheduleStore, from date: Date = Date()) -> FocusTomorrowStatus {
        let target = tomorrow(from: date)
        if let holiday = HolidayCalendarStore.shared.day(on: target) {
            if holiday.isOffDay {
                return .holiday(name: holiday.name)
            }
            let mapped = SpecialWorkDayStore.shared.targetDate(for: target)
            return .makeUpWorkDay(targetDate: mapped)
        }
        return .firstClass(hour: firstCourseHour(on: target, store: store))
    }
}

/// 明天安排详情：状态 + 明日课程 + 调休补课设置。
struct TomorrowPlanView: View {
    @EnvironmentObject private var scheduleStore: ScheduleStore
    @State private var status: FocusTomorrowStatus = .firstClass(hour: nil)
    @State private var showsSetting = false

    private var tomorrow: Date { FocusPlanResolver.tomorrow() }

    private var tomorrowCourses: [Course] {
        FocusPlanResolver.courses(on: tomorrow, store: scheduleStore)
    }

    private var isMakeUp: Bool {
        if case .makeUpWorkDay = status { return true }
        return false
    }

    var body: some View {
        List {
            Section("明天") {
                HStack(spacing: 12) {
                    Image(systemName: status.symbol)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(dateTitle).font(.headline)
                        Text(status.value).font(.subheadline).foregroundStyle(.secondary)
                        if let detail = status.detail {
                            Text(detail).font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.vertical, 2)

                if isMakeUp {
                    Button {
                        showsSetting = true
                    } label: {
                        Label("设置按哪天课表上课", systemImage: "calendar.badge.clock")
                    }
                }
            }

            Section(isMakeUp ? "明天的课程（按补课日期）" : "明天的课程") {
                if tomorrowCourses.isEmpty {
                    Text("明天没有课程安排。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(tomorrowCourses) { course in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(course.startTime)-\(course.endTime) \(course.name)")
                                .font(.subheadline.weight(.medium))
                            if !course.location.isEmpty {
                                Text(course.location).font(.caption).foregroundStyle(.secondary)
                            }
                            if !course.teacher.isEmpty {
                                Text(course.teacher).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Section("说明") {
                Text("数据来源为节假日安排（holiday-cn）。调休上班日会按照你设置的日期显示课程，与原版一致。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("明天安排")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsSetting = true
                } label: {
                    Image(systemName: "calendar.badge.clock")
                }
                .accessibilityLabel("调休补课设置")
            }
        }
        .sheet(isPresented: $showsSetting) {
            SpecialWorkDaySettingView(originDate: tomorrow)
        }
        .task { await load() }
        .refreshable { await load(force: true) }
    }

    private var dateTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd"
        return "\(formatter.string(from: tomorrow)) \(FocusPlanResolver.weekdayName(for: tomorrow))"
    }

    @MainActor
    private func load(force: Bool = false) async {
        await HolidayCalendarStore.shared.refreshIfNeeded(force: force)
        status = FocusPlanResolver.tomorrowStatus(store: scheduleStore)
    }
}

/// 调休补课设置（对应 Android 版 ChangeCourseUI）。
struct SpecialWorkDaySettingView: View {
    let originDate: Date

    @Environment(\.dismiss) private var dismiss
    @State private var targetDate = Date()

    private var originKey: String { HolidayCalendarStore.key(for: originDate) }

    var body: some View {
        NavigationStack {
            Form {
                Section("调休日期") {
                    Text("\(originKey)（\(FocusPlanResolver.weekdayName(for: originDate))）")
                    Text("设置后，聚焦页与明天安排会按所选日期的课表显示。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("按哪天课表上课") {
                    DatePicker("选择日期", selection: $targetDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                    Text("将实行：\(HolidayCalendarStore.key(for: targetDate))（\(FocusPlanResolver.weekdayName(for: targetDate))）")
                        .font(.footnote)
                }

                Section {
                    NavigationLink {
                        FeatureDetailView(feature: FeatureCatalog.all.first { $0.id == 38 } ?? FeatureCatalog.all[0])
                    } label: {
                        Label("查询学校调休安排", systemImage: "newspaper")
                    }
                }
            }
            .navigationTitle("调休补课")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        SpecialWorkDayStore.shared.setTarget(HolidayCalendarStore.key(for: targetDate), for: originDate)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("恢复默认", role: .destructive) {
                        SpecialWorkDayStore.shared.removeTarget(for: originDate)
                        dismiss()
                    }
                }
            }
        }
    }
}
