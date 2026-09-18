import SwiftUI

/// 小组件配色，跟随浅色/深色模式。
struct WidgetPalette {
    let canvas: Color
    let title: Color
    let cardText: Color
    let subtle: Color
    let separator: Color
    let dayBackground: Color
    let tintOpacity: Double

    static func resolve(_ scheme: ColorScheme) -> WidgetPalette {
        if scheme == .dark {
            return WidgetPalette(
                canvas: Color(red: 0.05, green: 0.05, blue: 0.06),
                title: Color(red: 0.95, green: 0.90, blue: 0.85),
                cardText: Color(red: 0.98, green: 0.95, blue: 0.92),
                subtle: Color.white.opacity(0.62),
                separator: Color.white.opacity(0.12),
                dayBackground: Color.white.opacity(0.07),
                tintOpacity: 0.38
            )
        }
        return WidgetPalette(
            canvas: Color(red: 1.00, green: 0.97, blue: 0.95),
            title: Color(red: 0.55, green: 0.29, blue: 0.13),
            cardText: Color(red: 0.26, green: 0.16, blue: 0.11),
            subtle: Color(red: 0.45, green: 0.35, blue: 0.30),
            separator: Color.black.opacity(0.10),
            dayBackground: Color.black.opacity(0.05),
            tintOpacity: 0.52
        )
    }
}

/// 小组件渲染所需的全部数据（与 WidgetKit 解耦，便于独立预览）。
struct WeeklyScheduleViewData {
    var date: Date
    var week: Int
    var monday: Date?
    var courses: [WidgetCourseSnapshot]
}

enum SchedulePalette {
    /// 应用内「今天」使用的强调色（AppTheme.accent）。
    static let todayAccent = Color(red: 0.18, green: 0.48, blue: 0.96)
    static let courseTints: [Color] = [
        Color(red: 0.18, green: 0.48, blue: 0.96),
        Color(red: 0.22, green: 0.76, blue: 0.58),
        Color(red: 0.55, green: 0.38, blue: 0.94),
        Color(red: 0.98, green: 0.62, blue: 0.29),
        Color(red: 0.94, green: 0.45, blue: 0.60)
    ]
}

struct WeeklyScheduleWidgetView: View {
    let data: WeeklyScheduleViewData

    @Environment(\.colorScheme) private var colorScheme

    private static let weekdayNames = ["一", "二", "三", "四", "五"]

    private var palette: WidgetPalette { .resolve(colorScheme) }

    var body: some View {
        VStack(spacing: 5) {
            header
            dayHeaderRow
            TimelineCanvas(courses: data.courses, palette: palette)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    /// 顶部：日期 + 周次 + 星期 + 实时时间。
    private var header: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(dateText)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text("第 \(data.week) 周")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .padding(.horizontal, 6)
                .padding(.vertical, 1.5)
                .background(Capsule().fill(palette.dayBackground))
            Text(weekdayText)
                .font(.system(size: 11, weight: .semibold))
            Spacer(minLength: 0)
            Image(systemName: "clock")
                .font(.system(size: 10, weight: .bold))
            Text(Date(), style: .time)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(palette.title)
    }

    /// 星期表头：今天用强调色高亮。
    private var dayHeaderRow: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { weekday in
                let isToday = Self.isToday(weekday, monday: data.monday)
                VStack(spacing: 1) {
                    Text("周\(Self.weekdayNames[weekday - 1])")
                        .font(.system(size: 9.5, weight: .bold))
                    Text(dateLabel(for: weekday))
                        .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundStyle(isToday ? Color.white : palette.title)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isToday ? SchedulePalette.todayAccent : palette.dayBackground)
                )
            }
        }
        .frame(height: 30)
    }

    private var dateText: String {
        Self.formatter("MM/dd").string(from: data.date)
    }

    private var weekdayText: String {
        Self.formatter("EEEE").string(from: data.date)
    }

    private func dateLabel(for weekday: Int) -> String {
        guard let monday = data.monday,
              let date = Calendar.current.date(byAdding: .day, value: weekday - 1, to: monday) else { return "--/--" }
        return Self.formatter("MM/dd").string(from: date)
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = format
        return formatter
    }

    private static func isToday(_ weekday: Int, monday: Date?) -> Bool {
        guard let monday,
              let date = Calendar.current.date(byAdding: .day, value: weekday - 1, to: monday) else { return false }
        return Calendar.current.isDateInToday(date)
    }
}

/// 按时间比例排布的课表主体，压缩午休时段，和应用内课表一致。
private struct TimelineCanvas: View {
    let courses: [WidgetCourseSnapshot]
    let palette: WidgetPalette

    private static let lunchStart = 12 * 60 + 10.0
    private static let lunchEnd = 14 * 60.0
    private static let lunchFactor = 0.12
    private static let gridStart = 8 * 60.0
    private static let gridEnd = 18 * 60 + 30.0

    var body: some View {
        GeometryReader { proxy in
            let columnWidth = proxy.size.width / 5
            let height = proxy.size.height
            ZStack(alignment: .topLeading) {
                ForEach(1...4, id: \.self) { index in
                    Rectangle()
                        .fill(palette.separator)
                        .frame(width: 0.8)
                        .offset(x: CGFloat(index) * columnWidth)
                }
                ForEach(1...5, id: \.self) { weekday in
                    ForEach(courses.filter { $0.weekday == weekday }.sorted { $0.startTime < $1.startTime }) { course in
                        let top = offset(for: minutes(course.startTime), height: height)
                        let bottom = offset(for: minutes(course.endTime), height: height)
                        let cardHeight = max(24, bottom - top)
                        ScheduleCourseCard(course: course, height: cardHeight, palette: palette)
                            .frame(width: max(24, columnWidth - 5), height: cardHeight)
                            .offset(x: CGFloat(weekday - 1) * columnWidth + 2.5, y: top)
                    }
                }
            }
        }
    }

    private func offset(for minute: Double, height: CGFloat) -> CGFloat {
        let start = Self.compressed(Self.gridStart)
        let end = Self.compressed(Self.gridEnd)
        let value = Self.compressed(minute) - start
        return max(0, min(height, CGFloat(value / (end - start)) * height))
    }

    private static func compressed(_ minute: Double) -> Double {
        if minute <= lunchStart { return minute }
        if minute <= lunchEnd { return lunchStart + (minute - lunchStart) * lunchFactor }
        return lunchStart + (lunchEnd - lunchStart) * lunchFactor + (minute - lunchEnd)
    }

    private func minutes(_ text: String) -> Double {
        let parts = text.split(separator: ":").compactMap { Double($0) }
        guard let hour = parts.first else { return 0 }
        return hour * 60 + (parts.count > 1 ? parts[1] : 0)
    }
}

private struct ScheduleCourseCard: View {
    let course: WidgetCourseSnapshot
    let height: CGFloat
    let palette: WidgetPalette

    private var tint: Color {
        SchedulePalette.courseTints[abs(course.colorIndex) % SchedulePalette.courseTints.count]
    }

    private var title: String {
        course.teacher.isEmpty ? course.name : "\(course.name) @\(course.teacher)"
    }

    private var showsEndTime: Bool { height >= 46 }

    var body: some View {
        VStack(spacing: 1) {
            Text(course.startTime)
                .font(.system(size: 7, weight: .semibold, design: .rounded))
                .foregroundStyle(palette.subtle)
            Spacer(minLength: 0)
            Text(title)
                .font(.system(size: 8.5, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(showsEndTime ? 3 : 2)
                .minimumScaleFactor(0.6)
            if !course.location.isEmpty {
                Text(shortLocation)
                    .font(.system(size: 7, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer(minLength: 0)
            if showsEndTime {
                Text(course.endTime)
                    .font(.system(size: 7, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.subtle)
            }
        }
        .foregroundStyle(palette.cardText)
        .padding(.horizontal, 2)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(tint.opacity(palette.tintOpacity), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(tint.opacity(0.35), lineWidth: 0.5)
        }
    }

    private var shortLocation: String {
        course.location
            .components(separatedBy: "（").first!
            .replacingOccurrences(of: "教学楼", with: "教")
            .replacingOccurrences(of: "科教楼", with: "科教")
            .replacingOccurrences(of: "综合楼", with: "综")
            .replacingOccurrences(of: "大学生活动中心", with: "大活")
    }
}
