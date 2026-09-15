import SwiftUI

struct ScheduleView: View {
    @EnvironmentObject private var scheduleStore: ScheduleStore
    @State private var selectedDay = 1
    @State private var showingAdd = false
    @State private var exportMessage: String?

    private var selectedCourses: [Course] {
        scheduleStore.courses(on: selectedDay)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                dayPicker

                if selectedCourses.isEmpty {
                    ContentUnavailableView(
                        "当天没有课程",
                        systemImage: "calendar.badge.checkmark",
                        description: Text("可手动添加；后续将接入教务系统自动同步。")
                    )
                    .padding(.vertical, 54)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(selectedCourses) { course in
                            CourseRow(course: course)
                                .contextMenu {
                                    Button("删除课程", systemImage: "trash", role: .destructive) {
                                        scheduleStore.remove(id: course.id)
                                    }
                                }
                        }
                    }
                }

                if scheduleStore.courses.isEmpty {
                    Button("载入演示课表", systemImage: "sparkles") {
                        scheduleStore.installPreviewData()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(16)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("课表")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("导出到日历", systemImage: "calendar.badge.plus") {
                    Task { await exportToCalendar() }
                }
                .disabled(scheduleStore.courses.isEmpty)
                Button("添加课程", systemImage: "plus") {
                    showingAdd = true
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddCourseView(defaultWeekday: selectedDay)
        }
        .alert("日历", isPresented: Binding(
            get: { exportMessage != nil },
            set: { if !$0 { exportMessage = nil } }
        )) {
            Button("好") { exportMessage = nil }
        } message: {
            Text(exportMessage ?? "")
        }
    }

    private var dayPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(1...7, id: \.self) { day in
                    Button {
                        withAnimation(.snappy) { selectedDay = day }
                    } label: {
                        Text(Course.weekdayNames[day - 1])
                            .font(.subheadline.weight(selectedDay == day ? .bold : .medium))
                            .foregroundStyle(selectedDay == day ? .white : .primary)
                            .padding(.horizontal, 15)
                            .frame(height: 42)
                            .background {
                                if selectedDay == day {
                                    Capsule().fill(AppTheme.accent)
                                }
                            }
                            .adaptiveGlass(cornerRadius: 21, interactive: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
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
