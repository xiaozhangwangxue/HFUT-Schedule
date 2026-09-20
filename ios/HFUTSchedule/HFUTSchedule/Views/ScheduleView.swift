import SwiftUI

struct ScheduleView: View {
    @EnvironmentObject private var scheduleStore: ScheduleStore
    @EnvironmentObject private var notificationManager: CourseNotificationManager
    @State private var selectedWeek = 1
    @State private var didChooseInitialWeek = false
    @State private var showingAdd = false
    @State private var showingAcademicSync = false
    @State private var showingWeekPicker = false
    @State private var selectedCourse: Course?
    @State private var exportMessage: String?
    @AppStorage("scheduleShowsWeekend") private var showsWeekend = false

    private var termStart: Date? {
        ScheduleCalendar.termStart(from: scheduleStore.courses)
    }

    private var selectedCourses: [Course] {
        ScheduleCalendar.courses(scheduleStore.courses, in: selectedWeek)
    }

    private var visibleWeekdays: [Int] {
        showsWeekend ? Array(1...7) : Array(1...5)
    }

    private var visibleCourses: [Course] {
        selectedCourses.filter { visibleWeekdays.contains($0.weekday) }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    ScheduleWeekHeader(week: selectedWeek, termStart: termStart, visibleWeekdays: visibleWeekdays)

                    if visibleCourses.isEmpty {
                        ContentUnavailableView(
                            emptyTitle,
                            systemImage: "calendar.badge.checkmark",
                            description: Text(emptyDescription)
                        )
                        .frame(minHeight: 520)
                    } else {
                        TimetableGridView(
                            courses: visibleCourses,
                            visibleWeekdays: visibleWeekdays,
                            week: selectedWeek,
                            termStart: termStart
                        ) { selectedCourse = $0 }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .padding(.bottom, 92)
            }
            .simultaneousGesture(weekSwipeGesture)

            WeekStepper(
                week: selectedWeek,
                canGoBack: selectedWeek > 1,
                canGoForward: selectedWeek < 20,
                onBack: { moveWeek(-1) },
                onCurrent: { goToCurrentWeek() },
                onForward: { moveWeek(1) },
                onChoose: { showingWeekPicker = true }
            )
            .padding(.trailing, 16)
            .padding(.bottom, 12)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(showsWeekend ? "隐藏周末" : "显示周末", systemImage: showsWeekend ? "calendar.badge.minus" : "calendar.badge.plus") {
                    withAnimation(.snappy) { showsWeekend.toggle() }
                }
                Button("教务同步", systemImage: "arrow.triangle.2.circlepath") {
                    showingAcademicSync = true
                }
                Menu("课表操作", systemImage: "ellipsis.circle") {
                    Button("选择周次", systemImage: "calendar") { showingWeekPicker = true }
                    Button("导出到系统日历", systemImage: "calendar.badge.plus") {
                        Task { await exportToCalendar() }
                    }
                    .disabled(scheduleStore.courses.isEmpty)
                    Button("添加课程", systemImage: "plus") { showingAdd = true }
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddCourseView(defaultWeekday: Calendar.current.component(.weekday, from: Date()).mondayBasedWeekday)
        }
        .sheet(isPresented: $showingAcademicSync) {
            AcademicScheduleSyncView()
        }
        .sheet(isPresented: $showingWeekPicker) {
            WeekPickerSheet(selectedWeek: $selectedWeek)
                .presentationDetents([.medium])
                .presentationBackground(.ultraThinMaterial)
        }
        .navigationDestination(isPresented: selectedCourseBinding) {
            if let selectedCourse {
                CourseDetailView(course: selectedCourse)
            }
        }
        .alert("日历", isPresented: Binding(
            get: { exportMessage != nil },
            set: { if !$0 { exportMessage = nil } }
        )) {
            Button("好") { exportMessage = nil }
        } message: {
            Text(exportMessage ?? "")
        }
        .task { try? await notificationManager.reschedule(for: scheduleStore.courses) }
        .onAppear { chooseInitialWeekIfNeeded() }
        .onChange(of: scheduleStore.courses) { _, _ in chooseInitialWeekIfNeeded(force: true) }
        .onChange(of: scheduleStore.courses) { _, courses in
            Task { try? await notificationManager.reschedule(for: courses) }
        }
    }

    private var selectedCourseBinding: Binding<Bool> {
        Binding(
            get: { selectedCourse != nil },
            set: { if !$0 { selectedCourse = nil } }
        )
    }

    private var navigationTitle: String {
        guard let monday = ScheduleCalendar.startDate(of: selectedWeek, termStart: termStart) else {
            return "第 \(selectedWeek) 周"
        }
        let todayWeekday = Calendar.current.component(.weekday, from: Date()).mondayBasedWeekday
        let date = ScheduleCalendar.calendar.date(byAdding: .day, value: todayWeekday - 1, to: monday) ?? monday
        return "\(date.formatted(.dateTime.month(.twoDigits).day(.twoDigits))) 第\(selectedWeek)周 \(Course.weekdayNames[todayWeekday - 1])"
    }

    private var emptyTitle: String {
        if !showsWeekend && selectedCourses.contains(where: { $0.weekday > 5 }) {
            return "本周课程仅在周末"
        }
        return "第 \(selectedWeek) 周没有课程"
    }

    private var emptyDescription: String {
        if !showsWeekend && selectedCourses.contains(where: { $0.weekday > 5 }) {
            return "点击右上角“显示周末”查看周六、周日课程。"
        }
        return "左右滑动切换周次，或点击右下角周次返回本周。"
    }

    private var weekSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height),
                      abs(value.predictedEndTranslation.width) > 70 else { return }
                moveWeek(value.predictedEndTranslation.width < 0 ? 1 : -1)
            }
    }

    private func moveWeek(_ delta: Int) {
        let target = min(20, max(1, selectedWeek + delta))
        guard target != selectedWeek else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 1)) { selectedWeek = target }
    }

    private func goToCurrentWeek() {
        let week = ScheduleCalendar.currentWeek(termStart: termStart)
        withAnimation(.spring(response: 0.38, dampingFraction: 1)) { selectedWeek = week }
    }

    private func chooseInitialWeekIfNeeded(force: Bool = false) {
        guard force || !didChooseInitialWeek else { return }
        selectedWeek = ScheduleCalendar.currentWeek(termStart: termStart)
        didChooseInitialWeek = true
    }

    @MainActor
    private func exportToCalendar() async {
        do {
            let count = try await CalendarExporter().export(scheduleStore.courses)
            exportMessage = "已写入 \(count) 个课程日程。"
        } catch {
            exportMessage = error.localizedDescription
        }
    }
}

private extension Int {
    var mondayBasedWeekday: Int {
        self == 1 ? 7 : self - 1
    }
}

private struct AddCourseView: View {
    @EnvironmentObject private var scheduleStore: ScheduleStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var teacher = ""
    @State private var location = ""
    @State private var weekday: Int
    @State private var startTime = Date()
    @State private var endTime = Date().addingTimeInterval(100 * 60)

    init(defaultWeekday: Int) {
        _weekday = State(initialValue: defaultWeekday)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("课程") {
                    TextField("课程名称", text: $name)
                    TextField("教师（可选）", text: $teacher)
                    TextField("地点（可选）", text: $location)
                }
                Section("时间") {
                    Picker("星期", selection: $weekday) {
                        ForEach(1...7, id: \.self) { value in
                            Text(Course.weekdayNames[value - 1]).tag(value)
                        }
                    }
                    DatePicker("开始", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("结束", selection: $endTime, displayedComponents: .hourAndMinute)
                }
            }
            .navigationTitle("添加课程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        scheduleStore.add(
                            Course(
                                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                teacher: teacher,
                                location: location,
                                weekday: weekday,
                                startTime: startTime.formatted(date: .omitted, time: .shortened),
                                endTime: endTime.formatted(date: .omitted, time: .shortened),
                                colorIndex: Int.random(in: 0..<5)
                            )
                        )
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || endTime <= startTime)
                }
            }
        }
    }
}
