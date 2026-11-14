import SwiftUI

/// 环形进度图标：对应上游 CircleProgressIcon，用于「正在上课」的课程。
struct CircularProgressIcon: View {
    let progress: Double
    var tint: Color = .accentColor
    var size: CGFloat = 22
    var lineWidth: CGFloat = 2.5

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.6), value: progress)
        }
        .frame(width: size, height: size)
    }
}

/// 就业：对应上游 WorkScreen（就业网 + 就业系统学生端）。
struct WorkServiceView: View {
    private struct Entry: Identifiable {
        let title: String
        let subtitle: String
        let symbol: String
        let url: URL
        var id: String { title + url.absoluteString }
    }

    private let entries: [Entry] = [
        Entry(title: "就业系统（学生端）", subtitle: "默认密码为 xs_身份证号后 6 位", symbol: "person.text.rectangle", url: URL(string: "http://jyxt.hfut.edu.cn/Pro_Student/Login.aspx")!),
        Entry(title: "就业网（合肥校区）", subtitle: "招聘、实习与双选", symbol: "briefcase", url: URL(string: "https://gdjy.hfut.edu.cn/")!),
        Entry(title: "就业网（宣城校区）", subtitle: "宣城校区就业信息", symbol: "briefcase.fill", url: URL(string: "https://xcjy.hfut.edu.cn/")!),
        Entry(title: "就业检索", subtitle: "职位与宣讲会检索", symbol: "magnifyingglass", url: URL(string: "https://dc.bysjy.com.cn/")!)
    ]

    var body: some View {
        List {
            Section("就业服务") {
                ForEach(entries) { entry in
                    NavigationLink {
                        PortalWebView(url: entry.url)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: entry.symbol)
                                .foregroundStyle(.secondary)
                                .frame(width: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.title).font(.subheadline.weight(.medium))
                                Text(entry.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Section("说明") {
                Text("就业系统由学校独立维护，首次登录请使用「xs_身份证号后 6 位」作为默认密码，登录后可自行修改。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("就业服务")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    PortalWebView(url: entries[0].url)
                } label: {
                    Text("就业系统")
                }
            }
        }
    }
}

/// 校车 v2：同步上游出行视图、自然星期班次与实时发车过滤。
struct BusScheduleView: View {
    @EnvironmentObject private var studentStore: AcademicStudentStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var routes: [CampusBusRoute] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var startQuery = ""
    @State private var endQuery = ""
    @State private var mode = CampusBusDisplayMode.upcoming
    @State private var selectedDate = Date()
    @State private var now = Date()
    @State private var holidayDay: HolidayDay?

    private var selection: CampusBusSelection {
        CampusBusService.select(routes, mode: mode, date: selectedDate, now: now,
                                from: startQuery, to: endQuery)
    }

    private var startPoints: [String] { Array(Set(routes.map(\.from))).sorted() }
    private var endPoints: [String] { Array(Set(routes.map(\.to))).sorted() }

    var body: some View {
        List {
            Section {
                Picker("校车安排", selection: $mode) {
                    ForEach(CampusBusDisplayMode.allCases) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                if mode == .upcoming {
                    DatePicker("出行日期", selection: $selectedDate,
                               in: Calendar.current.startOfDay(for: now)...,
                               displayedComponents: .date)
                }
                HStack {
                    Menu {
                        Button("全部起点") { startQuery = "" }
                        ForEach(startPoints, id: \.self) { point in
                            Button(point) { startQuery = point }
                        }
                    } label: {
                        Text(startQuery.isEmpty ? "起点" : startQuery)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityLabel("起点：\(startQuery.isEmpty ? "全部" : startQuery)")
                    Button {
                        swap(&startQuery, &endQuery)
                    } label: {
                        Image(systemName: "arrow.left.arrow.right")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("交换起点和终点")
                    Menu {
                        Button("全部终点") { endQuery = "" }
                        ForEach(endPoints, id: \.self) { point in
                            Button(point) { endQuery = point }
                        }
                    } label: {
                        Text(endQuery.isEmpty ? "终点" : endQuery)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .accessibilityLabel("终点：\(endQuery.isEmpty ? "全部" : endQuery)")
                }
            }

            if mode == .upcoming,
               let advisory = CampusBusService.holidayAdvisory(for: holidayDay),
               let feature = FeatureCatalog.all.first(where: { $0.nativeDestination == .holidays }) {
                Section {
                    NavigationLink {
                        FeatureDetailView(feature: feature)
                    } label: {
                        Label(advisory, systemImage: "calendar.badge.exclamationmark")
                            .font(.footnote)
                    }
                }
            }

            if isLoading {
                HStack { ProgressView(); Text("正在读取校车时刻…").foregroundStyle(.secondary) }
            } else if let errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(errorMessage).font(.footnote).foregroundStyle(.secondary)
                    Button("重新读取") { Task { await load() } }
                }
            } else if selection.routes.isEmpty {
                ContentUnavailableView(selection.emptyMessage, systemImage: "bus")
            }

            ForEach(selection.routes) { route in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "bus").foregroundStyle(.secondary)
                        Text("\(route.from) → \(route.to)").font(.headline)
                        Spacer()
                        Text("\(route.count) 辆").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text("\(route.time) · \(route.week) · \(route.place)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if route.points.count > 1 {
                        RouteLineView(points: route.points)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("校车")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    PortalWebView(url: CampusBusService.pageURL)
                } label: {
                    Image(systemName: "network")
                }
                .accessibilityLabel("查看网页最新数据")
            }
        }
        .task {
            // 只有学籍明确指出具体校区时才预选，合肥区域本身无法区分屯溪路与翡翠湖。
            let campus = studentStore.info?.campus ?? ""
            if startQuery.isEmpty, endQuery.isEmpty,
               let keyword = ["翡翠湖", "屯溪路", "宣城"].first(where: campus.contains) {
                startQuery = keyword
            }
            await load()
            if !startQuery.isEmpty,
               let point = startPoints.first(where: { $0.contains(startQuery) }) {
                startQuery = point
            }
        }
        .task {
            now = Date()
            while !Task.isCancelled {
                let delay = CampusBusService.secondsUntilNextMinute(from: Date())
                do { try await Task.sleep(for: .seconds(delay)) }
                catch { break }
                now = Date()
            }
        }
        .task(id: selectedDate) {
            await HolidayCalendarStore.shared.refreshIfNeeded()
            holidayDay = HolidayCalendarStore.shared.day(on: selectedDate)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { now = Date() }
        }
        .refreshable { await load() }
    }

    @MainActor
    private func load() async {
        isLoading = routes.isEmpty
        errorMessage = nil
        now = Date()
        do {
            routes = try await CampusBusService.fetchRoutes()
            if routes.isEmpty {
                errorMessage = "校车时刻解析失败，可能是学校网页结构变动，可点右上角按钮查看网页最新数据。"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

/// 线路示意：起点 → 途经站 → 终点。
private struct RouteLineView: View {
    let points: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                ForEach(Array(points.enumerated()), id: \.offset) { index, _ in
                    Circle()
                        .fill(index == 0 || index == points.count - 1 ? Color.accentColor : Color.secondary.opacity(0.5))
                        .frame(width: index == 0 || index == points.count - 1 ? 7 : 5,
                               height: index == 0 || index == points.count - 1 ? 7 : 5)
                    if index < points.count - 1 {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(height: 1)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            HStack(alignment: .top, spacing: 4) {
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    Text(point)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(2)
                }
            }
        }
    }
}
