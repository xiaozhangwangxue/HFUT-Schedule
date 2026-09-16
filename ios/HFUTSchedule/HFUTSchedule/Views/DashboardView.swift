import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var scheduleStore: ScheduleStore
    @EnvironmentObject private var studentStore: AcademicStudentStore
    @State private var section = 0

    private let serviceColumns = [GridItem(.flexible()), GridItem(.flexible())]

    private var todayIndex: Int {
        Calendar.current.component(.weekday, from: Date()).mondayBasedWeekday
    }

    private var todayCourses: [Course] {
        scheduleStore.courses(on: todayIndex).sorted { $0.startTime < $1.startTime }
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
                            NavigationLink(value: feature) {
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
                NavigationLink(value: feature(39)) { Image(systemName: "icloud") }
                NavigationLink(value: feature(15)) { Image(systemName: "bell") }
                NavigationLink(value: feature(42)) { Image(systemName: "rectangle.portrait.and.arrow.right") }
            }
        }
        .navigationDestination(for: CampusFeature.self) { feature in
            FeatureDetailView(feature: feature)
        }
    }

    private var campusSnapshot: some View {
        LazyVGrid(columns: serviceColumns, spacing: 8) {
            NavigationLink(value: feature(1)) {
                snapshotItem("一卡通", value: "点击查看", icon: "creditcard")
            }
            NavigationLink(value: feature(3)) {
                snapshotItem("宿舍电费", value: "点击查询", icon: "bolt")
            }
            snapshotItem(greetingTitle, value: greetingValue, icon: "face.smiling")
            NavigationLink(value: feature(4)) {
                snapshotItem("校园网", value: "查看状态", icon: "globe")
            }
        }
        .padding(10)
        .adaptiveGlass(cornerRadius: 22, tint: AppTheme.accent.opacity(0.035))
    }

    @ViewBuilder
    private var courseList: some View {
        if todayCourses.isEmpty {
            ContentUnavailableView("今天没有课程", systemImage: "calendar.badge.checkmark")
                .frame(minHeight: 180)
                .adaptiveGlass(cornerRadius: 22)
        } else {
            ForEach(todayCourses) { course in
                NavigationLink {
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

    private func snapshotItem(_ title: String, value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.body).foregroundStyle(.primary).lineLimit(1)
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

    private var greetingTitle: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 0..<6: "今晚"
        case 6..<11: "今天"
        case 11..<14: "中午"
        case 14..<18: "下午"
        default: "今晚"
        }
    }

    private var greetingValue: String {
        let name = studentStore.info?.name.nonEmpty
        return name.map { "\($0)，\(shortGreeting)" } ?? shortGreeting
    }

    private var shortGreeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 0..<6: "早点休息"
        case 6..<11: "早上好"
        case 11..<14: "午安"
        case 14..<18: "继续加油"
        default: "晚上好"
        }
    }

    private func status(for course: Course) -> String {
        let now = Date().formatted(date: .omitted, time: .shortened)
        if now < course.startTime { return "未开始" }
        if now <= course.endTime { return "进行中" }
        return "已结束"
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
