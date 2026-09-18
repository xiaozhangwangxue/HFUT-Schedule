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
    var weekIndices: [Int]? = nil
    var dates: [String]? = nil
    var source: String? = nil
    var details: CourseDetails? = nil

    static let preview: [Course] = [
        Course(name: "高等数学", teacher: "", location: "教学楼 A201", weekday: 2, startTime: "08:00", endTime: "09:40", colorIndex: 0),
        Course(name: "大学英语", teacher: "", location: "教学楼 B305", weekday: 2, startTime: "14:00", endTime: "15:40", colorIndex: 1),
        Course(name: "程序设计", teacher: "", location: "计算机楼 102", weekday: 4, startTime: "10:00", endTime: "11:40", colorIndex: 2)
    ]
}

struct CourseDetails: Codable, Hashable {
    var lessonID: Int?
    var type: String?
    var weeksText: String?
    var classmatesCount: Int?
    var credits: Double?
    var teachers: [CourseTeacher]
    var department: String?
    var examMode: String?
    var code: String?
    var semester: String?
    var className: String?
    var scheduleText: String?
    var remark: String?

    init(
        lessonID: Int? = nil,
        type: String? = nil,
        weeksText: String? = nil,
        classmatesCount: Int? = nil,
        credits: Double? = nil,
        teachers: [CourseTeacher] = [],
        department: String? = nil,
        examMode: String? = nil,
        code: String? = nil,
        semester: String? = nil,
        className: String? = nil,
        scheduleText: String? = nil,
        remark: String? = nil
    ) {
        self.lessonID = lessonID
        self.type = type
        self.weeksText = weeksText
        self.classmatesCount = classmatesCount
        self.credits = credits
        self.teachers = teachers
        self.department = department
        self.examMode = examMode
        self.code = code
        self.semester = semester
        self.className = className
        self.scheduleText = scheduleText
        self.remark = remark
    }
}

struct CourseTeacher: Codable, Hashable, Identifiable {
    var name: String
    var age: Int?
    var title: String?
    var type: String?

    var id: String { "\(name)|\(title ?? "")|\(type ?? "")" }
}

extension Course {
    static let weekdayNames = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    var weekdayName: String {
        guard (1...7).contains(weekday) else { return "未安排" }
        return Self.weekdayNames[weekday - 1]
    }

    var weekDescription: String? {
        guard let weekIndices, !weekIndices.isEmpty else { return nil }
        let sorted = weekIndices.sorted()
        if sorted.count == 1 { return "第 \(sorted[0]) 周" }
        return "第 \(sorted.first!)–\(sorted.last!) 周"
    }
}
