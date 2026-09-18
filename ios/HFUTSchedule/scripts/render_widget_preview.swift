// 小组件渲染预览：把 WeeklyScheduleWidgetView 渲染成 PNG，便于在装机前检查排版。
// 用法：
//   swiftc -parse-as-library Shared/WeeklyScheduleWidgetView.swift scripts/render_widget_preview.swift \
//     -target arm64-apple-macos13.0 -o /tmp/widget_preview && /tmp/widget_preview /tmp/widget.png
import SwiftUI
import AppKit

struct WidgetCourseSnapshot: Identifiable, Equatable {
    var id: UUID
    var name: String
    var teacher: String
    var location: String
    var weekday: Int
    var startTime: String
    var endTime: String
    var colorIndex: Int
    var weekIndices: [Int]?
    var dates: [String]?
}

private func course(
    _ name: String,
    _ teacher: String,
    _ location: String,
    _ weekday: Int,
    _ start: String,
    _ end: String,
    _ colorIndex: Int
) -> WidgetCourseSnapshot {
    WidgetCourseSnapshot(
        id: UUID(),
        name: name,
        teacher: teacher,
        location: location,
        weekday: weekday,
        startTime: start,
        endTime: end,
        colorIndex: colorIndex,
        weekIndices: nil,
        dates: nil
    )
}

private func sampleData() -> WeeklyScheduleViewData {
    var calendar = Calendar(identifier: .gregorian)
    calendar.firstWeekday = 2
    let today = Date()
    let monday = calendar.date(
        from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
    )!
    return WeeklyScheduleViewData(
        date: today,
        week: 2,
        monday: monday,
        courses: [
            course("高等数学", "", "教学楼 A101", 1, "08:00", "09:40", 0),
            course("程序设计", "", "计算机楼 102", 1, "10:00", "11:40", 1),
            course("大学英语", "", "教学楼 B305", 2, "10:00", "11:40", 0),
            course("思想道德与法治", "", "教学楼 A201", 2, "14:00", "15:40", 4),
            course("线性代数", "", "教学楼 A101", 3, "10:00", "11:40", 1),
            course("大学物理", "", "实验楼 C203", 4, "10:00", "11:40", 3),
            course("体育", "", "体育场", 4, "14:00", "15:40", 2),
            course("大学英语", "", "教学楼 B305", 5, "08:00", "09:40", 3),
            course("高等数学", "", "教学楼 A101", 5, "10:00", "11:40", 1),
            course("程序设计", "", "计算机楼 102", 5, "15:50", "17:30", 0)
        ]
    )
}

@MainActor
private func render(scheme: ColorScheme, size: CGSize) -> NSImage? {
    let view = WeeklyScheduleWidgetView(data: sampleData())
        .frame(width: size.width, height: size.height)
        .background(WidgetPalette.resolve(scheme).canvas)
        .environment(\.colorScheme, scheme)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 3
    return renderer.nsImage
}

@main
struct WidgetPreviewRenderer {
    @MainActor
    static func main() {
        let outputDirectory = CommandLine.arguments.count > 1
            ? CommandLine.arguments[1]
            : "/tmp/hfut-widget-preview"
        try? FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)

        let size = CGSize(width: 360, height: 340)
        for (name, scheme) in [("dark", ColorScheme.dark), ("light", ColorScheme.light)] {
            guard let image = render(scheme: scheme, size: size),
                  let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else {
                print("渲染失败: \(name)")
                continue
            }
            let path = "\(outputDirectory)/widget-\(name).png"
            try? png.write(to: URL(fileURLWithPath: path))
            print("已输出 \(path)")
        }
    }
}
