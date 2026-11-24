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
        if let manual = manualTermStart(defaults: .standard) { return manual }
        let derived = derivedTermStart(from: courses)
        let cloud = cloudTermStart()
        // 云端学期开始日更权威，但只在和课程数据一致（相差不超过 4 周）时采用，
        // 避免云端配置还没更新时把日期算错。
        if let derived, let cloud {
            return abs(derived.timeIntervalSince(cloud)) <= 28 * 86_400 ? cloud : derived
        }
        return cloud ?? derived
    }

    static func manualTermStart(defaults: UserDefaults) -> Date? {
        guard defaults.object(forKey: AppSettingsKey.autoTermStart) != nil,
              !defaults.bool(forKey: AppSettingsKey.autoTermStart) else { return nil }
        let timestamp = defaults.double(forKey: AppSettingsKey.manualTermStart)
        guard timestamp > 0, timestamp.isFinite else { return nil }
        return calendar.startOfDay(for: Date(timeIntervalSince1970: timestamp))
    }

    private static func cloudTermStart() -> Date? {
        let text = CampusCloudConfigStore.shared.termStartDate
        guard !text.isEmpty, let date = isoDate(text) else { return nil }
        return calendar.startOfDay(for: date)
    }

    /// 由课程数据推导学期开始日：对所有课程投票，避免混入上一学期的课程导致顶部日期错位。
    private static func derivedTermStart(from courses: [Course]) -> Date? {
        var votes: [Date: Int] = [:]
        for course in courses {
            guard let week = course.weekIndices?.sorted().first,
                  let text = course.dates?.sorted().first,
                  let date = isoDate(text) else { continue }
            let days = (week - 1) * 7 + max(0, course.weekday - 1)
            if let start = calendar.date(byAdding: .day, value: -days, to: date) {
                votes[calendar.startOfDay(for: start), default: 0] += 1
            }
        }
        return votes.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.key > rhs.key
        }.first?.key
    }

    static func currentWeek(termStart: Date?) -> Int {
        guard let termStart else { return 1 }
        let today = calendar.startOfDay(for: Date())
        let days = calendar.dateComponents([.day], from: termStart, to: today).day ?? 0
        guard days >= 0 else { return 1 }
        return max(1, days / 7 + 1)
    }

    static func startDate(of week: Int, termStart: Date?) -> Date? {
        guard let termStart else { return nil }
        return calendar.date(byAdding: .day, value: (week - 1) * 7, to: termStart)
    }

    static func courses(_ courses: [Course], in week: Int) -> [Course] {
        let monday = startDate(of: week, termStart: termStart(from: courses))
        let lower = monday.map(HolidayCalendarStore.key)
        let upper = monday.flatMap { calendar.date(byAdding: .day, value: 7, to: $0) }.map(HolidayCalendarStore.key)
        let filtered = courses.filter { course in
            if let dates = course.dates, !dates.isEmpty, let lower, let upper {
                return dates.contains { $0 >= lower && $0 < upper }
            }
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

    static func clockString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
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
    var week: Int = 1
    var termStart: Date? = nil
    var onCreateAt: ((Int, Double) -> Void)? = nil
    let onSelect: (Course) -> Void

    @AppStorage("timetableShowsTimeLine") private var showsTimeLine = false
    @AppStorage(AppSettingsKey.showTeacherInSquare) private var showsTeacher = false
    @AppStorage(AppSettingsKey.mergeConflictingSquares) private var mergesConflicts = false
    @AppStorage(AppSettingsKey.backgroundBlur) private var backgroundBlur = 0.35
    @AppStorage("calendarHourHeight") private var savedHourHeight = 68.0
    @AppStorage("calendarTextScale") private var textScale = 1.0
    @AppStorage("calendarPadding") private var cardPadding = 3.0
    @AppStorage("calendarOpacity") private var cardOpacity = 0.38
    @AppStorage("teacherDisplayMode") private var teacherMode = -1
    @State private var now = Date()
    @State private var conflictingCourses: [Course] = []
    @State private var showsConflicts = false
    @State private var pinchStartHeight: Double?

    private var startHour: Double { min(8, courses.map { Self.decimalTime($0.startTime) }.min() ?? 8) }
    private var endHour: Double { max(22, courses.map { Self.decimalTime($0.endTime) }.max() ?? 22) }
    private var hourHeight: CGFloat { CGFloat(min(140, max(40, savedHourHeight))) }

    private var totalHeight: CGFloat { y(for: endHour) }

    /// 当前显示周 == 今天所在周，且今天在显示列内时，返回今天所在列索引。
    private var todayColumn: Int? {
        guard showsTimeLine else { return nil }
        let currentWeek = ScheduleCalendar.currentWeek(termStart: termStart)
        guard week == currentWeek else { return nil }
        let todayWeekday = ScheduleCalendar.calendar.component(.weekday, from: now)
        let mondayBased = todayWeekday == 1 ? 7 : todayWeekday - 1
        guard visibleWeekdays.contains(mondayBased) else { return nil }
        return visibleWeekdays.firstIndex(of: mondayBased)
    }

    private var currentTimeFraction: Double {
        let components = ScheduleCalendar.calendar.dateComponents([.hour, .minute], from: now)
        return Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60
    }

    var body: some View {
        GeometryReader { proxy in
            let columnWidth = proxy.size.width / CGFloat(visibleWeekdays.count)
            ZStack(alignment: .topLeading) {
                timetableBackground
                Color.clear.contentShape(Rectangle())
                    .gesture(SpatialTapGesture(count: 2).onEnded { value in
                        guard let onCreateAt, columnWidth > 0 else { return }
                        let column = min(visibleWeekdays.count - 1, max(0, Int(value.location.x / columnWidth)))
                        // Invert the same compressed lunchtime geometry used by cards.
                        var low = startHour, high = endHour
                        for _ in 0..<20 {
                            let middle = (low + high) / 2
                            if y(for: middle) < value.location.y { low = middle } else { high = middle }
                        }
                        onCreateAt(visibleWeekdays[column], (low * 4).rounded() / 4)
                    })

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

                    Group {
                        if item.mergedCourses.count > 1 {
                            Button {
                                conflictingCourses = item.mergedCourses
                                showsConflicts = true
                            } label: { courseCard(item) }
                        } else if item.course.source == "custom-event" {
                            Button { onSelect(item.course) } label: { courseCard(item) }
                        } else {
                            SourceAnchoredNavigationLink(sourceID: "timetable-course-\(item.course.id)-\(item.course.weekday)") {
                                if item.course.source == "exam" { TimetableExamDestination(courseID: item.course.id) }
                                else { CourseDetailView(course: item.course) }
                            } label: { courseCard(item) }
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(width: width, height: max(34, bottom - top))
                    .offset(x: x, y: top)
                    .contextMenu {
                        Button("查看课程详情", systemImage: "info.circle") { onSelect(item.course) }
                    }
                }

                if let todayColumn {
                    let lineY = y(for: currentTimeFraction)
                    let columnWidth = proxy.size.width / CGFloat(visibleWeekdays.count)
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(Color.red)
                        .frame(width: max(0, columnWidth - 4), height: 1.6)
                        .offset(x: CGFloat(todayColumn) * columnWidth + 2, y: lineY)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(height: totalHeight)
        .simultaneousGesture(MagnifyGesture().onChanged { value in
            if pinchStartHeight == nil { pinchStartHeight = savedHourHeight }
            savedHourHeight = min(140, max(40, (pinchStartHeight ?? 68) * value.magnification))
        }.onEnded { _ in pinchStartHeight = nil })
        .confirmationDialog("选择冲突课程", isPresented: $showsConflicts, titleVisibility: .visible) {
            ForEach(conflictingCourses) { course in
                Button("\(course.name) · \(course.location)") { onSelect(course) }
            }
            Button("取消", role: .cancel) { }
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { date in
            now = date
        }
    }

    private func courseCard(_ item: PositionedCourse) -> some View {
        TimetableCourseCard(course: item.course, mergedCourses: item.mergedCourses,
            showsTeacher: teacherMode < 0 ? showsTeacher : teacherMode == 2 || (teacherMode == 1 && (item.course.details?.teachers.count ?? (item.course.teacher.contains("、") ? 2 : 1)) > 1),
            textScale: textScale, cardPadding: cardPadding, cardOpacity: cardOpacity)
    }

    private var positionedCourses: [PositionedCourse] {
        var result: [PositionedCourse] = []
        for day in visibleWeekdays {
            let dayCourses = courses.filter { $0.weekday == day }.sorted { $0.startTime < $1.startTime }
            var grouped = Set<UUID>()
            for course in dayCourses {
                guard !grouped.contains(course.id) else { continue }
                let start = Self.decimalTime(course.startTime)
                let end = Self.decimalTime(course.endTime)
                let overlaps = dayCourses.filter {
                    Self.decimalTime($0.startTime) < end && Self.decimalTime($0.endTime) > start
                }
                let ordered = overlaps.sorted { $0.startTime < $1.startTime || ($0.startTime == $1.startTime && $0.name < $1.name) }
                if mergesConflicts, ordered.count > 1, ordered.allSatisfy({ $0.source != "exam" && $0.source != "custom-event" }) {
                    ordered.forEach { grouped.insert($0.id) }
                    result.append(PositionedCourse(
                        course: ordered[0],
                        columnIndex: 0,
                        totalColumns: 1,
                        mergedCourses: ordered
                    ))
                    continue
                }
                grouped.insert(course.id)
                result.append(PositionedCourse(
                    course: course,
                    columnIndex: ordered.firstIndex(of: course) ?? 0,
                    totalColumns: max(1, ordered.count),
                    mergedCourses: [course]
                ))
            }
        }
        return result
    }

    /// 课程表背景图（可调前景模糊），对应上游「课程表-背景」。
    @ViewBuilder
    private var timetableBackground: some View {
        if let url = TimetableBackgroundStore.fileURL,
           let data = try? Data(contentsOf: url),
           let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .blur(radius: backgroundBlur * 18)
                .opacity(0.55)
                .allowsHitTesting(false)
        }
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
    var mergedCourses: [Course] = []
    var id: String { "\(course.id.uuidString)|\(course.weekday)" }
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
    var mergedCourses: [Course] = []
    var showsTeacher: Bool = false
    var textScale = 1.0
    var cardPadding = 3.0
    var cardOpacity = 0.38

    private var tint: Color {
        if course.source == "exam" { return .red }
        return [AppTheme.accent, AppTheme.mint, AppTheme.violet, .orange, .pink][abs(course.colorIndex) % 5]
    }

    var body: some View {
        VStack(spacing: 1) {
            Text(course.startTime)
                .font(.system(size: 8 * textScale, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 1)
            Text(title)
                .font(.system(size: 10.5 * textScale, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(5)
                .minimumScaleFactor(0.72)
            if !course.location.isEmpty {
                Text(simplified(course.location))
                    .font(.system(size: 9 * textScale, weight: .medium))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 1)
            Text(course.endTime)
                .font(.system(size: 8 * textScale, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, cardPadding)
        .padding(.vertical, cardPadding + 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .adaptiveGlass(cornerRadius: 7, tint: tint.opacity(cardOpacity), interactive: true)
    }

    private func simplified(_ place: String) -> String {
        place
            .components(separatedBy: "（").first!
            .replacingOccurrences(of: "教学楼", with: "教")
            .replacingOccurrences(of: "科教楼", with: "科教")
            .replacingOccurrences(of: "综合楼", with: "综")
            .replacingOccurrences(of: "大学生活动中心", with: "大活")
    }

    private var title: String {
        if mergedCourses.count > 1 {
            return mergedCourses
                .map { showsTeacher && !$0.teacher.isEmpty ? "\($0.name)@\($0.teacher)" : $0.name }
                .joined(separator: " / ")
        }
        return (course.source == "exam" ? "考试\n" : "") + course.name + (showsTeacher && !course.teacher.isEmpty ? "@\(course.teacher)" : "")
    }
}

struct WeekStepper: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let week: Int
    let canGoBack: Bool
    let canGoForward: Bool
    let onBack: () -> Void
    let onCurrent: () -> Void
    let onForward: () -> Void
    let onChoose: () -> Void
    @GestureState private var dragOffset: CGFloat = 0

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
        .offset(x: reduceMotion ? 0 : dragOffset)
        .simultaneousGesture(DragGesture(minimumDistance: 12)
            .updating($dragOffset) { value, state, _ in
                state = max(-60, min(60, value.translation.width * 0.6))
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height), abs(value.translation.width) > 30 else { return }
                if value.translation.width < 0, canGoForward { onForward() }
                if value.translation.width > 0, canGoBack { onBack() }
            })
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.78), value: dragOffset)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if canGoForward { onForward() }
            case .decrement: if canGoBack { onBack() }
            @unknown default: break
            }
        }
    }
}

struct WeekPickerSheet: View {
    @Binding var selectedWeek: Int
    var maximumWeek: Int = 20
    var courses: [Course] = []
    var termStart: Date? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        AppNavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 12) {
                    ForEach(1...maximumWeek, id: \.self) { week in
                        Button {
                            selectedWeek = week
                            dismiss()
                        } label: {
                            VStack(spacing: 6) {
                                HStack {
                                    Text("第 \(week) 周").font(.caption.weight(.semibold))
                                    Spacer()
                                    if week == selectedWeek { Image(systemName: "checkmark.circle.fill") }
                                }
                                WeekScheduleThumbnail(courses: ScheduleCalendar.courses(courses, in: week))
                                    .frame(height: 144)
                            }.padding(10)
                                .background(week == selectedWeek ? AppTheme.accent.opacity(0.15) : Color.secondary.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 14))
                        }.buttonStyle(.plain)
                    }
                }
                .padding(18)
            }
            .navigationTitle("选择周次")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct WeekScheduleThumbnail: View {
    let courses: [Course]

    var body: some View {
        Canvas { context, size in
            let column = size.width / 7
            for day in 0...7 {
                var path = Path()
                path.move(to: CGPoint(x: CGFloat(day) * column, y: 0))
                path.addLine(to: CGPoint(x: CGFloat(day) * column, y: size.height))
                context.stroke(path, with: .color(.secondary.opacity(0.15)), lineWidth: 0.5)
            }
            for course in courses {
                let start = minute(course.startTime), end = minute(course.endTime)
                guard (1...7).contains(course.weekday), end > start else { continue }
                let rect = CGRect(x: CGFloat(course.weekday - 1) * column + 1,
                    y: CGFloat(max(0, start - 420)) / 1020 * size.height,
                    width: max(1, column - 2), height: max(3, CGFloat(end - start) / 1020 * size.height))
                let colors: [Color] = [AppTheme.accent, .teal, .purple, .orange, .pink]
                context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(colors[abs(course.colorIndex) % colors.count].opacity(0.7)))
            }
        }.accessibilityLabel("\(courses.count)个课程时段的缩略课表")
    }

    private func minute(_ time: String) -> Int {
        let values = time.split(separator: ":").compactMap { Int($0) }
        return (values.first ?? 0) * 60 + (values.count > 1 ? values[1] : 0)
    }
}

struct CourseDetailSheet: View {
    let course: Course

    var body: some View {
        AppNavigationStack {
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
