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
                NativeProgramView()
            case .library:
                NativeLibraryView()
            case .campusLife:
                NativeCampusLifeView()
            case .holidays:
                NativeHolidayView()
            case .express:
                NativeExpressView()
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
            NavigationLink { CourseDetailView(course: course) } label: {
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

private struct NativeLibraryView: View {
    @State private var query = ""
    @State private var books: [OfficialLibraryBook] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section("馆藏与电子书检索") {
                TextField("书名、作者或 ISBN", text: $query)
                Button("搜索", systemImage: "magnifyingglass") { Task { await search() } }.disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
            }
            ForEach(books) { book in
                VStack(alignment: .leading, spacing: 5) {
                    Text(book.title).font(.headline)
                    Text([book.author.joined(separator: "、"), book.publishers, String(book.year)].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(Array((book.gc ?? []).prefix(3).enumerated()), id: \.offset) { _, place in
                        Text("\(place.cp) · \(place.in) · \(place.js ?? "馆藏")").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            if let errorMessage { ContentUnavailableView("图书检索失败", systemImage: "books.vertical", description: Text(errorMessage)) }
        }
        .overlay { if isLoading { ProgressView("正在检索馆藏…") } }
    }

    @MainActor private func search() async {
        isLoading = true; errorMessage = nil
        do { books = try await OfficialCampusAPIClient.shared.searchLibrary(keyword: query.trimmingCharacters(in: .whitespacesAndNewlines)) }
        catch { errorMessage = error.localizedDescription }
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
    var body: some View {
        List {
            Section("校园身份") {
                LabeledContent("校区", value: appState.campus.rawValue)
                if let info = studentStore.info {
                    LabeledContent("姓名", value: info.name)
                    LabeledContent("学院", value: info.department)
                    LabeledContent("专业", value: info.major)
                }
            }
            Section("学习概览") {
                LabeledContent("今日课程", value: "\(scheduleStore.courses(on: Calendar.current.component(.weekday, from: Date()) == 1 ? 7 : Calendar.current.component(.weekday, from: Date()) - 1).count) 门")
                LabeledContent("本地课程总数", value: "\(Set(scheduleStore.courses.map(\.name)).count) 门")
            }
            Section("校园工具") {
                Label("校园卡、宿舍电费、洗衣、快递均已在查询中心提供原生入口", systemImage: "checkmark.seal.fill")
            }
        }
    }
}

private struct NativeHolidayView: View {
    struct Payload: Decodable { let year: String; let days: [Day] }
    struct Day: Decodable, Identifiable { let name: String; let date: String; let isOffDay: Bool; var id: String { "\(date)|\(name)" } }
    @State private var days: [Day] = []
    @State private var errorMessage: String?

    var body: some View {
        List {
            ForEach(days) { day in
                LabeledContent(day.name) {
                    Text("\(day.date) · \(day.isOffDay ? "休" : "班")").foregroundStyle(day.isOffDay ? .green : .orange)
                }
            }
            if let errorMessage { ContentUnavailableView("节假日读取失败", systemImage: "calendar.badge.exclamationmark", description: Text(errorMessage)) }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    @MainActor private func load() async {
        do {
            let year = Calendar.current.component(.year, from: Date())
            let url = URL(string: "https://raw.githubusercontent.com/Chiu-xaH/holiday-cn/master/\(year).json")!
            let (data, _) = try await URLSession.shared.data(from: url)
            days = try JSONDecoder().decode(Payload.self, from: data).days
        } catch { errorMessage = error.localizedDescription }
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
