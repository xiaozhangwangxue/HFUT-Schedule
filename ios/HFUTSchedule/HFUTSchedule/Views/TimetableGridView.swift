import SwiftUI

enum ScheduleCalendar {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = .current
        calendar.firstWeekday = 2
        return calendar
    }()

    static func termStart(from courses: [Course]) -> Date? {
        for course in courses {
            guard let week = course.weekIndices?.sorted().first,
                  let text = course.dates?.sorted().first,
                  let date = isoDate(text) else { continue }
            let days = (week - 1) * 7 + max(0, course.weekday - 1)
            if let start = calendar.date(byAdding: .day, value: -days, to: date) {
                return calendar.startOfDay(for: start)
            }
        }
        return nil
    }

    static func currentWeek(termStart: Date?) -> Int {
        guard let termStart else { return 1 }
        let today = calendar.startOfDay(for: Date())
        let days = calendar.dateComponents([.day], from: termStart, to: today).day ?? 0
        guard days >= 0 else { return 1 }
        return min(20, max(1, days / 7 + 1))
    }

    static func startDate(of week: Int, termStart: Date?) -> Date? {
        guard let termStart else { return nil }
        return calendar.date(byAdding: .day, value: (week - 1) * 7, to: termStart)
    }

    static func courses(_ courses: [Course], in week: Int) -> [Course] {
        let filtered = courses.filter { course in
            guard let weeks = course.weekIndices, !weeks.isEmpty else { return true }
            return weeks.contains(week)
        }
        var seen = Set<String>()
        return filtered.filter { course in
            let key = [course.name, course.teacher, course.location, String(course.weekday), course.startTime, course.endTime]
                .joined(separator: "|")
            return seen.insert(key).inserted
        }
    }

    static func isoDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)
    }
}

struct ScheduleWeekHeader: View {
    let week: Int
    let termStart: Date?
    let visibleWeekdays: [Int]

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width / CGFloat(visibleWeekdays.count)
            HStack(spacing: 0) {
                ForEach(visibleWeekdays, id: \.self) { day in
                    let date = date(for: day)
                    let isToday = date.map { ScheduleCalendar.calendar.isDateInToday($0) } ?? false
                    VStack(spacing: 3) {
                        Text(Self.shortWeekdays[day - 1])
                            .font(.caption2.weight(.semibold))
                        Text(date?.formatted(.dateTime.month(.twoDigits).day(.twoDigits)) ?? "--/--")
                            .font(.system(size: 10, weight: isToday ? .bold : .medium, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(isToday ? AppTheme.accent : .primary)
                    .frame(width: width, height: 46)
                    .background {
                        if isToday { Capsule().fill(AppTheme.accent.opacity(0.16)).padding(.horizontal, 3) }
                    }
                }
            }
        }
        .frame(height: 46)
        .adaptiveGlass(cornerRadius: 16)
        .accessibilityElement(children: .contain)
    }

    private func date(for day: Int) -> Date? {
        guard let monday = ScheduleCalendar.startDate(of: week, termStart: termStart) else { return nil }
        return ScheduleCalendar.calendar.date(byAdding: .day, value: day - 1, to: monday)
    }

    private static let shortWeekdays = ["一", "二", "三", "四", "五", "六", "日"]
}

struct TimetableGridView: View {
    let courses: [Course]
    let visibleWeekdays: [Int]
    let onSelect: (Course) -> Void

    private let startHour = 8.0
    private let endHour = 22.0
    private let hourHeight: CGFloat = 68

    private var totalHeight: CGFloat { y(for: endHour) }

    var body: some View {
        GeometryReader { proxy in
            let columnWidth = proxy.size.width / CGFloat(visibleWeekdays.count)
            ZStack(alignment: .topLeading) {
                TimelineGridShape(columnCount: visibleWeekdays.count)
                    .stroke(.secondary.opacity(0.22), style: StrokeStyle(lineWidth: 0.65, dash: [4, 5]))

                ForEach(positionedCourses) { item in
                    let available = columnWidth - 4
                    let gap: CGFloat = 1.5
                    let width = max(22, (available - gap * CGFloat(item.totalColumns - 1)) / CGFloat(item.totalColumns))
                    let dayColumn = visibleWeekdays.firstIndex(of: item.course.weekday) ?? 0
                    let x = CGFloat(dayColumn) * columnWidth + 2 + CGFloat(item.columnIndex) * (width + gap)
                    let top = y(for: Self.decimalTime(item.course.startTime))
                    let bottom = y(for: Self.decimalTime(item.course.endTime))

                    SourceAnchoredNavigationLink(
                        sourceID: "timetable-course-\(item.course.id.uuidString)"
                    ) {
                        CourseDetailView(course: item.course)
                    } label: {
                        TimetableCourseCard(course: item.course)
                    }
                    .buttonStyle(.plain)
                    .frame(width: width, height: max(34, bottom - top))
                    .offset(x: x, y: top)
                    .contextMenu {
                        Button("查看课程详情", systemImage: "info.circle") { onSelect(item.course) }
                    }
                }
            }
        }
        .frame(height: totalHeight)
    }

    private var positionedCourses: [PositionedCourse] {
        var result: [PositionedCourse] = []
        for day in visibleWeekdays {
            let dayCourses = courses.filter { $0.weekday == day }.sorted { $0.startTime < $1.startTime }
            for course in dayCourses {
                let start = Self.decimalTime(course.startTime)
                let end = Self.decimalTime(course.endTime)
                let overlaps = dayCourses.filter {
                    Self.decimalTime($0.startTime) < end && Self.decimalTime($0.endTime) > start
                }
                let ordered = overlaps.sorted { $0.startTime < $1.startTime || ($0.startTime == $1.startTime && $0.name < $1.name) }
                result.append(PositionedCourse(
                    course: course,
                    columnIndex: ordered.firstIndex(of: course) ?? 0,
                    totalColumns: max(1, ordered.count)
                ))
            }
        }
        return result
    }

    private func y(for hour: Double) -> CGFloat {
        let lunchStart = 12.0 + 10.0 / 60.0
        let lunchEnd = 14.0
        let factor = 0.10
        if hour <= lunchStart { return CGFloat(max(0, hour - startHour)) * hourHeight }
        let before = CGFloat(lunchStart - startHour) * hourHeight
        if hour <= lunchEnd { return before + CGFloat(hour - lunchStart) * hourHeight * factor }
        return before + CGFloat(lunchEnd - lunchStart) * hourHeight * factor + CGFloat(hour - lunchEnd) * hourHeight
    }

    static func decimalTime(_ text: String) -> Double {
        let values = text.split(separator: ":").compactMap { Double($0) }
        guard let hour = values.first else { return 0 }
        return hour + (values.count > 1 ? values[1] / 60 : 0)
    }
}

private struct PositionedCourse: Identifiable {
    let course: Course
    let columnIndex: Int
    let totalColumns: Int
    var id: UUID { course.id }
}

private struct TimelineGridShape: Shape {
    let columnCount: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for column in 0...columnCount {
            let x = rect.width * CGFloat(column) / CGFloat(columnCount)
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))
        }
        return path
    }
}

private struct TimetableCourseCard: View {
    let course: Course

    private var tint: Color {
        [AppTheme.accent, AppTheme.mint, AppTheme.violet, .orange, .pink][abs(course.colorIndex) % 5]
    }

    var body: some View {
        VStack(spacing: 1) {
            Text(course.startTime)
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 1)
            Text(course.name + (course.teacher.isEmpty ? "" : "@\(course.teacher)"))
                .font(.system(size: 10.5, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(5)
                .minimumScaleFactor(0.72)
            if !course.location.isEmpty {
                Text(simplified(course.location))
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 1)
            Text(course.endTime)
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .adaptiveGlass(cornerRadius: 7, tint: tint.opacity(0.38), interactive: true)
    }

    private func simplified(_ place: String) -> String {
        place
            .components(separatedBy: "（").first!
            .replacingOccurrences(of: "教学楼", with: "教")
            .replacingOccurrences(of: "科教楼", with: "科教")
            .replacingOccurrences(of: "综合楼", with: "综")
            .replacingOccurrences(of: "大学生活动中心", with: "大活")
    }
}

struct WeekStepper: View {
    let week: Int
    let canGoBack: Bool
    let canGoForward: Bool
    let onBack: () -> Void
    let onCurrent: () -> Void
    let onForward: () -> Void
    let onChoose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onBack) { Image(systemName: "chevron.left") }
                .disabled(!canGoBack)
            Button(action: onCurrent) {
                Text("第 \(week) 周")
                    .font(.subheadline.weight(.semibold))
                    .contentTransition(.numericText(value: Double(week)))
                    .frame(minWidth: 62)
            }
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in onChoose() })
            Button(action: onForward) { Image(systemName: "chevron.right") }
                .disabled(!canGoForward)
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppTheme.accent)
        .frame(height: 52)
        .padding(.horizontal, 12)
        .adaptiveGlass(cornerRadius: 19, tint: AppTheme.accent.opacity(0.08), interactive: true)
    }
}

struct WeekPickerSheet: View {
    @Binding var selectedWeek: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                    ForEach(1...20, id: \.self) { week in
                        Button("第 \(week) 周") {
                            selectedWeek = week
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(week == selectedWeek ? AppTheme.accent : .secondary.opacity(0.32))
                    }
                }
                .padding(18)
            }
            .navigationTitle("选择周次")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct CourseDetailSheet: View {
    let course: Course

    var body: some View {
        NavigationStack {
            List {
                Section("课程") {
                    LabeledContent("名称", value: course.name)
                    if !course.teacher.isEmpty { LabeledContent("教师", value: course.teacher) }
                    if !course.location.isEmpty { LabeledContent("教室", value: course.location) }
                }
                Section("时间") {
                    LabeledContent("星期", value: course.weekdayName)
                    LabeledContent("上课时间", value: "\(course.startTime)–\(course.endTime)")
                    if let weeks = course.weekDescription { LabeledContent("周次", value: weeks) }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("课程详情")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
