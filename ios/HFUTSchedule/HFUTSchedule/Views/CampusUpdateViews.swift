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

/// 校车 v2：对应上游 BusScreenV2，按星期分组展示班次与线路。
struct BusScheduleView: View {
    @State private var routes: [CampusBusRoute] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var startQuery = ""
    @State private var endQuery = ""
    @State private var selectedWeek: String?

    private var weeks: [String] {
        Array(Set(routes.map(\.week).filter { !$0.isEmpty })).sorted { lhs, rhs in
            weekOrder(lhs) < weekOrder(rhs)
        }
    }

    private var filtered: [CampusBusRoute] {
        routes.filter { route in
            if let selectedWeek, route.week != selectedWeek { return false }
            if !startQuery.isEmpty, !route.from.localizedCaseInsensitiveContains(startQuery) { return false }
            if !endQuery.isEmpty, !route.to.localizedCaseInsensitiveContains(endQuery) { return false }
            return true
        }
    }

    var body: some View {
        List {
            Section("筛选") {
                TextField("起点", text: $startQuery)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("终点", text: $endQuery)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !weeks.isEmpty {
                    Picker("星期", selection: Binding(
                        get: { selectedWeek ?? "" },
                        set: { selectedWeek = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("全部").tag("")
                        ForEach(weeks, id: \.self) { week in
                            Text(week).tag(week)
                        }
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
            } else if filtered.isEmpty {
                Text("没有符合条件的班次。").font(.footnote).foregroundStyle(.secondary)
            }

            ForEach(filtered) { route in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "bus")
                            .foregroundStyle(.secondary)
                        Text("\(route.week) \(route.time)").font(.headline)
                        Spacer()
                        Text("\(route.count) 辆").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text("上车地点：\(route.place)")
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
            ToolbarItem(placement: .topBarTrailing) {
                Button(selectedWeek == nil ? "全部" : selectedWeek!) {
                    cycleWeek()
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func cycleWeek() {
        guard !weeks.isEmpty else { return }
        guard let current = selectedWeek, let index = weeks.firstIndex(of: current) else {
            selectedWeek = weeks.first
            return
        }
        selectedWeek = index == weeks.count - 1 ? nil : weeks[index + 1]
    }

    private func weekOrder(_ week: String) -> Int {
        // 学校表格里的分组是「周一至周五 / 周六 / 周日」
        if week.contains("周一至周五") || week.contains("工作日") { return 0 }
        let names = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        if let index = names.firstIndex(of: week) { return index }
        return names.firstIndex { week.hasPrefix($0) } ?? names.count
    }

    @MainActor
    private func load() async {
        isLoading = routes.isEmpty
        errorMessage = nil
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
