import SwiftUI

struct AcademicTermCoursesView: View {
    @State private var semesterID = AcademicPortal.currentSemesterID
    @State private var items: [AcademicTermCourse] = []
    @State private var query = ""
    @State private var error: String?
    @State private var loading = false
    @State private var loaded = false
    @State private var showingLogin = false
    var body: some View {
        List {
            Section("学期") {
                Stepper("学期代号 \(semesterID.formatted(.number.grouping(.never)))", value: $semesterID, in: 1...9999)
                Button("读取学期课程与教材") { Task { await load() } }.disabled(loading)
            }
            if let error { Text(error).foregroundStyle(.red) }
            if let notice = items.first?.textbookNotice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
            if loaded && items.isEmpty && error == nil { Text("本学期暂无课程，可切换学期后重新读取。").foregroundStyle(.secondary) }
            Button("重新登录教务系统", systemImage: "lock.shield") { showingLogin = true }
            ForEach(items.filter { query.isEmpty || "\($0.lesson.courseName) \($0.lesson.code ?? "") \($0.course.teacher)".localizedCaseInsensitiveContains(query) }) { item in
                AppNavigationLink { AcademicTermCourseDetailView(item: item) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.lesson.courseName).font(.headline)
                        Text([item.lesson.code, item.lesson.className, item.lesson.credits.map { "\($0.formatted()) 学分" }].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                        Text(item.lesson.scheduleText?.isEmpty == false ? item.lesson.scheduleText! : "尚未排课").font(.caption)
                        if !item.textbook.isEmpty { Text("教材：\(item.textbook)").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        }
        .navigationTitle("学期课程汇总")
        .searchable(text: $query, prompt: "课程、代码、教师")
        .task { await load() }.refreshable { await load() }
        .sheet(isPresented: $showingLogin, onDismiss: { Task { await load() } }) { AppNavigationStack { LoginPortalView() } }
        .overlay { if loading { ProgressView() } }
    }
    @MainActor private func load() async {
        guard !loading else { return }; loading = true; error = nil; defer { loading = false; loaded = true }
        do {
            let mode = AcademicConnectionMode(rawValue: UserDefaults.standard.string(forKey: "academicConnectionMode") ?? "") ?? .direct
            items = try await AcademicClient(mode: mode, cookies: CampusSessionStore.shared.allCookies).fetchTermCourses(semesterID: semesterID)
        } catch { AcademicServiceDiagnostics.record(context: "课程与教室查询", error: error); self.error = error.localizedDescription }
    }
}
private struct AcademicTermCourseDetailView: View {
    let item: AcademicTermCourse
    var body: some View {
        VStack(spacing: 0) {
            if !item.textbook.isEmpty || !item.specialTextbook.isEmpty {
                VStack(alignment: .leading) {
                    if !item.textbook.isEmpty { Text("教材：\(item.textbook)") }
                    if !item.specialTextbook.isEmpty { Text("补充教材：\(item.specialTextbook)") }
                }.font(.subheadline).frame(maxWidth: .infinity, alignment: .leading).padding().textSelection(.enabled)
            }
            CourseDetailView(course: item.course)
        }
    }
}

struct AcademicLessonIDsScheduleView: View {
    let lessonIDs: [Int]
    var title = "查询结果课表"
    @AppStorage("academicConnectionMode") private var connectionMode = AcademicConnectionMode.direct.rawValue
    @State private var courses: [Course]?
    @State private var error: String?
    var body: some View {
        Group {
            if let courses { AcademicSchedulePreviewView(courses: courses, title: title) }
            else if let error { ContentUnavailableView("排课读取失败", systemImage: "calendar.badge.exclamationmark", description: Text(error)) }
            else { ProgressView() }
        }
        .task { do { courses = try await AcademicClient(mode: AcademicConnectionMode(rawValue: connectionMode) ?? .direct, cookies: CampusSessionStore.shared.allCookies).lessonSchedule(lessonIDs: lessonIDs) } catch { AcademicServiceDiagnostics.record(context: "课程与教室查询", error: error); self.error = error.localizedDescription } }
    }
}

struct OfficialClassroomScheduleView: View {
    let roomID: Int
    let name: String
    @State private var semesterID = AcademicPortal.currentSemesterID
    @State private var courses: [Course]?
    @State private var error: String?
    var body: some View {
        VStack {
            Stepper("学期代号 \(semesterID.formatted(.number.grouping(.never)))", value: $semesterID, in: 1...9999).padding()
            if let courses { AcademicSchedulePreviewView(courses: courses, title: name) }
            else if let error { ContentUnavailableView("教室课表读取失败", systemImage: "door.left.hand.closed", description: Text(error)) }
            else { ProgressView() }
        }
        .navigationTitle(name)
        .task(id: semesterID) {
            courses = nil; error = nil
            do { courses = try await OfficialCampusAPIClient.shared.classroomSchedule(roomID: roomID, semesterID: semesterID) } catch { AcademicServiceDiagnostics.record(context: "课程与教室查询", error: error); self.error = error.localizedDescription }
        }
    }
}

struct ClassroomDayDetailView: View {
    let room: OfficialEmptyClassroom
    let date: Date
    @State private var selected: OfficialEmptyClassroom.Occupation?
    private var occupations: [OfficialEmptyClassroom.Occupation] { room.roomOccupationInfoVms ?? [] }
    private var freePeriods: [ClosedRange<Int>] { ClassroomTimeAxis.freePeriods(occupations) }
    var body: some View {
        List {
            Section {
                Text(date.formatted(date: .abbreviated, time: .omitted))
                Text(room.campusNameZh).font(.caption).foregroundStyle(.secondary)
                AppNavigationLink { OfficialClassroomScheduleView(roomID: room.id, name: room.nameZh) } label: { Label("整学期教室课表", systemImage: "calendar") }
            }
            Section("全天占用时间轴") {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4).fill(.green.opacity(0.25))
                        ForEach(Array(occupations.enumerated()), id: \.offset) { _, item in
                            if let low = ClassroomTimeAxis.minute(item.startTimeString), let high = ClassroomTimeAxis.minute(item.endTimeString), high > low {
                                let left = max(480, min(1320, low))
                                let right = max(left, min(1320, high))
                                Button { selected = item } label: { RoundedRectangle(cornerRadius: 3).fill(.orange) }
                                    .frame(width: max(2, proxy.size.width * CGFloat(right - left) / 840))
                                    .offset(x: proxy.size.width * CGFloat(left - 480) / 840)
                                    .accessibilityLabel("\(item.startTimeString)至\(item.endTimeString) \(item.activityName ?? item.activityType)")
                            }
                        }
                    }
                }.frame(height: 28)
                HStack { Text("08:00"); Spacer(); Text("15:00"); Spacer(); Text("22:00") }.font(.caption.monospacedDigit())
                Text("绿色为空闲；点击橙色时段查看占用详情。").font(.caption).foregroundStyle(.secondary)
            }
            Section("空闲时段") {
                ForEach(Array(freePeriods.enumerated()), id: \.offset) { _, period in Label("\(ClassroomTimeAxis.clock(period.lowerBound)) - \(ClassroomTimeAxis.clock(period.upperBound))", systemImage: "checkmark.circle").foregroundStyle(.green) }
                if freePeriods.isEmpty { Text("全天没有可用时段") }
            }
            Section("占用记录") {
                ForEach(Array(occupations.enumerated()), id: \.offset) { _, item in
                    Button { selected = item } label: {
                        VStack(alignment: .leading) {
                            Text("\(item.startTimeString) - \(item.endTimeString)").monospacedDigit()
                            Text([item.activityName, item.teacherName, item.activityType].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(room.nameZh)
        .alert("占用详情", isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) { Button("确定") { selected = nil } } message: {
            if let selected { Text([selected.activityName, selected.teacherName, selected.date, "\(selected.startTimeString) - \(selected.endTimeString)", selected.activityType].compactMap { $0 }.joined(separator: "\n")) }
        }
    }
}
