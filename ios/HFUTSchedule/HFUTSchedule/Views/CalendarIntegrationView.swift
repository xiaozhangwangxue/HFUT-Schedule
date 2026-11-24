import SwiftUI

struct CalendarIntegrationView: View {
    @EnvironmentObject private var schedule: ScheduleStore
    @EnvironmentObject private var records: AcademicRecordsStore
    @EnvironmentObject private var events: CustomEventStore
    @AppStorage(CalendarExporter.selectedCalendarKey) private var selectedCalendar = ""
    @State private var calendars: [CalendarAccountOption] = []
    @State private var status: String?
    @State private var busy = false
    @State private var includeExams = true
    @State private var includeEvents = true
    @State private var confirmClear = false
    @State private var semesterWeeks = 20
    private let exporter = CalendarExporter()

    private var occurrences: [PlatformScheduleOccurrence] {
        PlatformScheduleResolver.occurrences(courses: schedule.courses,
            exams: includeExams ? records.exams : [], events: includeEvents ? events.events : [],
            termStart: ScheduleCalendar.termStart(from: schedule.courses), semesterWeeks: semesterWeeks)
    }

    var body: some View {
        Form {
            Section("写入位置") {
                Picker("系统日历", selection: $selectedCalendar) {
                    Text("系统默认日历").tag("")
                    ForEach(calendars) { item in Text("\(item.title)（\(item.account)）").tag(item.id) }
                }
                Button("重新读取日历列表") { Task { await loadCalendars() } }
            }
            Section {
                Toggle("包含考试", isOn: $includeExams)
                Toggle("包含普通日程与截止事项", isOn: $includeEvents)
                Stepper("未指定周次的课程：\(semesterWeeks) 周", value: $semesterWeeks, in: 1...60)
                Text("有校方日期的课程按实际日期导出；其余课程按学期开始日和上课周次展开。未指定周次时使用这里设置的学期周数。")
                    .font(.footnote).foregroundStyle(.secondary)
                LabeledContent("本次实际日程", value: "\(occurrences.count) 项")
                if ScheduleCalendar.termStart(from: schedule.courses) == nil {
                    Text("部分课程没有学期日期，尚不能展开。请先同步课表或在课表设置中设置学期开始日。")
                        .font(.footnote).foregroundStyle(.orange)
                }
            } header: { Text("导出内容") }
            Section {
                Button("导入或更新日程") { perform { try await exporter.export(occurrences, calendarID: calendarID) } }
                    .disabled(occurrences.isEmpty || busy)
                Button("清理旧导出后重新导入") {
                    perform { try await exporter.export(occurrences, calendarID: calendarID, replacingPrevious: true) }
                }.disabled(occurrences.isEmpty || busy)
                Button("清除本 App 导出的日程", role: .destructive) { confirmClear = true }.disabled(busy)
                Text("重复导入会更新已导出的项目。清理只处理本 App 在所选日历中记录的导出项目，不会清空系统日历。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if busy { ProgressView() }
            if let status { Section { Text(status).font(.footnote).textSelection(.enabled) } }
        }
        .navigationTitle("系统日历")
        .task { await loadCalendars() }
        .confirmationDialog("清除所选日历中本 App 导出的日程？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("清除已导出的日程", role: .destructive) { perform { try await exporter.clearExported(calendarID: calendarID) } }
        }
    }

    private var calendarID: String? { selectedCalendar.isEmpty ? nil : selectedCalendar }
    private func loadCalendars() async {
        do { calendars = try await exporter.calendars() }
        catch { PlatformDiagnosticsStore.shared.record(context: "系统日历列表读取", error: error); status = error.localizedDescription }
    }
    private func perform(_ operation: @escaping @MainActor () async throws -> Int) {
        busy = true
        Task {
            defer { busy = false }
            do { status = "已处理 \(try await operation()) 项系统日历日程。" }
            catch { PlatformDiagnosticsStore.shared.record(context: "系统日历管理", error: error); status = error.localizedDescription }
        }
    }
}

struct SingleCalendarExportButton: View {
    let occurrence: PlatformScheduleOccurrence
    @State private var status: String?
    @State private var busy = false
    var body: some View {
        Button {
            busy = true
            Task { @MainActor in
                defer { busy = false }
                do {
                    _ = try await CalendarExporter().export([occurrence], calendarID: UserDefaults.standard.string(forKey: CalendarExporter.selectedCalendarKey))
                    status = "已添加到系统日历。"
                } catch { PlatformDiagnosticsStore.shared.record(context: "单项系统日历导出", error: error); status = error.localizedDescription }
            }
        } label: { Label(busy ? "正在添加…" : "添加到系统日历", systemImage: "calendar.badge.plus") }
            .disabled(busy)
            .alert("系统日历", isPresented: Binding(get: { status != nil }, set: { if !$0 { status = nil } })) {
                Button("好") { status = nil }
            } message: { Text(status ?? "") }
    }
}
