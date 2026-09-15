import Foundation

struct Course: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var teacher: String
    var location: String
    var weekday: Int
    var startTime: String
    var endTime: String
    var colorIndex: Int

    static let preview: [Course] = [
        Course(name: "高等数学", teacher: "", location: "教学楼 A201", weekday: 2, startTime: "08:00", endTime: "09:40", colorIndex: 0),
        Course(name: "大学英语", teacher: "", location: "教学楼 B305", weekday: 2, startTime: "14:00", endTime: "15:40", colorIndex: 1),
        Course(name: "程序设计", teacher: "", location: "计算机楼 102", weekday: 4, startTime: "10:00", endTime: "11:40", colorIndex: 2)
    ]
}

extension Course {
    static let weekdayNames = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    var weekdayName: String {
        guard (1...7).contains(weekday) else { return "未安排" }
        return Self.weekdayNames[weekday - 1]
    }
}
