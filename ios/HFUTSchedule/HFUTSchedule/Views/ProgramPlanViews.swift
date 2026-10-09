import SwiftUI

/// 培养方案：对应 Android 版 ProgramUI.kt —— 进度 + 模块树 + 课程列表 + 搜索 + 课程详情。
struct ProgramPlanView: View {
    @AppStorage("academicConnectionMode") private var connectionMode = AcademicConnectionMode.direct.rawValue
    @EnvironmentObject private var studentStore: AcademicStudentStore

    @State private var root: AcademicProgramNode?
    @State private var completion: AcademicProgramCompletion?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var keyword = ""
    @State private var selectedCourse: AcademicProgramCourse?

    private var courses: [AcademicProgramCourse] {
        root?.allCourses.sorted { $0.termText < $1.termText } ?? []
    }

    private var filteredCourses: [AcademicProgramCourse] {
        let trimmed = keyword.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return courses }
        return courses.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.code.localizedCaseInsensitiveContains(trimmed)
                || $0.type.localizedCaseInsensitiveContains(trimmed)
                || $0.department.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var planTitle: String {
        studentStore.info?.fields["培养方案"] ?? studentStore.info?.major ?? "方案安排"
    }

    var body: some View {
        List {
            if let completion {
                Section("进度") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("已修 \(format(completion.total.actual))/\(format(completion.total.full))")
                                .font(.headline)
                            Spacer()
                            Text(String(format: "%.1f%%", completion.total.ratio * 100))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: completion.total.ratio)
                            .tint(completion.total.ratio >= 1 ? .green : AppTheme.accent)
                        ForEach(completion.others) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(item.name).font(.caption.weight(.medium))
                                    Spacer()
                                    Text("\(format(item.actual))/\(format(item.full))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                ProgressView(value: item.ratio)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            if let root {
                Section(planTitle) {
                    if let credits = root.requiredCredits, credits > 0 {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("要求 \(format(credits)) 学分").font(.subheadline.weight(.semibold))
                            if let remark = root.remark {
                                Text(remark).font(.caption).foregroundStyle(.secondary)
                            }
                            ModuleCreditsBar(children: root.children)
                        }
                        .padding(.vertical, 4)
                    }
                    ForEach(root.children) { child in
                        NavigationLink {
                            ProgramModuleView(node: child, selectedCourse: $selectedCourse)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(moduleTitle(child)).font(.subheadline.weight(.medium))
                                if let remark = child.remark {
                                    Text(remark).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section("课程（\(filteredCourses.count)）") {
                    if filteredCourses.isEmpty {
                        Text("没有匹配的课程。").font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(filteredCourses) { course in
                        Button {
                            selectedCourse = course
                        } label: {
                            ProgramCourseRow(course: course)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if isLoading {
                HStack { ProgressView(); Text("正在读取培养方案…").foregroundStyle(.secondary) }
            } else if let errorMessage, root == nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text(errorMessage).font(.footnote).foregroundStyle(.secondary)
                    Button("重新读取") { Task { await load() } }
                }
            }
        }
        .searchable(text: $keyword, prompt: "搜索课程、类型或代码")
        .navigationTitle("培养方案")
        .navigationBarTitleDisplayMode(.inline)
        .task { if root == nil { await load() } }
        .refreshable { await load() }
        .sheet(item: $selectedCourse) { course in
            ProgramCourseDetailSheet(course: course)
        }
    }

    private func moduleTitle(_ node: AcademicProgramNode) -> String {
        guard let credits = node.requiredCredits, credits > 0 else { return node.title }
        return "\(node.title)（要求 \(format(credits)) 学分）"
    }

    private func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let mode = AcademicConnectionMode(rawValue: connectionMode) ?? .direct
            let client = AcademicClient(mode: mode, cookies: CampusSessionStore.shared.allCookies)
            async let tree = client.fetchProgramTree()
            async let done = client.fetchProgramCompletion()
            root = try await tree
            completion = try? await done
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

/// 模块页：递归展示子模块与课程（对应上游 ProgramChildrenUI）。
struct ProgramModuleView: View {
    let node: AcademicProgramNode
    @Binding var selectedCourse: AcademicProgramCourse?
    @State private var keyword = ""

    private var filteredCourses: [AcademicProgramCourse] {
        let trimmed = keyword.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return node.courses }
        return node.courses.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.code.localizedCaseInsensitiveContains(trimmed)
                || $0.type.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        List {
            if !node.children.isEmpty {
                Section(node.remark ?? "模块") {
                    ForEach(node.children) { child in
                        NavigationLink {
                            ProgramModuleView(node: child, selectedCourse: $selectedCourse)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(child.requiredCredits.map { "\(child.title)（要求 \($0.formatted()) 学分）" } ?? child.title)
                                    .font(.subheadline.weight(.medium))
                                if let remark = child.remark {
                                    Text(remark).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }

            if !node.courses.isEmpty {
                Section("课程（\(filteredCourses.count)）") {
                    ForEach(filteredCourses) { course in
                        Button {
                            selectedCourse = course
                        } label: {
                            ProgramCourseRow(course: course)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if node.children.isEmpty, node.courses.isEmpty {
                Text("该模块暂无课程信息。").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .searchable(text: $keyword, prompt: "搜索课程、类型或代码")
        .navigationTitle(node.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ProgramCourseRow: View {
    let course: AcademicProgramCourse

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(course.name).font(.subheadline.weight(.medium))
                if course.compulsory {
                    Text("必修")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(AppTheme.accent.opacity(0.15), in: Capsule())
                }
                Spacer(minLength: 0)
                Text(course.credits > 0 ? "\(course.credits.formatted()) 学分" : "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text([course.code, course.type, course.termText].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
            if !course.department.isEmpty || !course.weeks.isEmpty {
                Text([course.department, course.weeks].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// 模块学分构成条（对应上游 StackedBarChart）。
private struct ModuleCreditsBar: View {
    let children: [AcademicProgramNode]

    private var items: [(String, Double)] {
        children.compactMap { node in
            guard let credits = node.requiredCredits, credits > 0 else { return nil }
            return (node.title.replacingOccurrences(of: "课程", with: ""), credits)
        }
    }

    var body: some View {
        let total = items.reduce(0) { $0 + $1.1 }
        if items.isEmpty || total <= 0 {
            EmptyView()
        } else {
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Self.colors[index % Self.colors.count])
                            .frame(width: max(4, proxy.size.width * item.1 / total - 2))
                    }
                }
            }
            .frame(height: 8)
            .padding(.top, 2)
        }
    }

    private static let colors: [Color] = [AppTheme.accent, AppTheme.mint, AppTheme.violet, .orange, .pink, .teal]
}

/// 课程详情（对应上游 ProgramDetailInfo），并提供跳转查询入口。
struct ProgramCourseDetailSheet: View {
    let course: AcademicProgramCourse
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("课程") {
                    LabeledContent("名称", value: course.name)
                    if !course.type.isEmpty { LabeledContent("类型", value: course.type) }
                    if course.credits > 0 { LabeledContent("学分", value: course.credits.formatted()) }
                    if !course.code.isEmpty { LabeledContent("课程代码", value: course.code) }
                    LabeledContent("修读性质", value: course.compulsory ? "必修" : "选修")
                }
                if !course.terms.isEmpty || !course.weeks.isEmpty || !course.department.isEmpty {
                    Section("安排") {
                        if !course.terms.isEmpty { LabeledContent("学期", value: course.termText) }
                        if !course.weeks.isEmpty { LabeledContent("周次", value: course.weeks) }
                        if !course.department.isEmpty { LabeledContent("开课学院", value: course.department) }
                    }
                }
                if !course.remark.isEmpty {
                    Section("备注") { Text(course.remark).font(.footnote) }
                }
                Section("相关查询") {
                    NavigationLink {
                        OfficialCourseSearchView()
                    } label: {
                        Label("其他教学班开课查询", systemImage: "magnifyingglass")
                    }
                    NavigationLink {
                        OfficialClassroomSearchView()
                    } label: {
                        Label("教室状态查询", systemImage: "door.left.hand.open")
                    }
                    NavigationLink {
                        OfficialFailRateView()
                    } label: {
                        Label("挂科率查询", systemImage: "percent")
                    }
                }
            }
            .navigationTitle(course.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
