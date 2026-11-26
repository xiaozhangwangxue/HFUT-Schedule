import Foundation

struct AcademicTermCourse: Identifiable {
    var id: String { lesson.id }
    let lesson: AcademicLesson
    let textbook: String
    let specialTextbook: String
    var textbookNotice: String? = nil
    var course: Course { AcademicClient.detailCourse(for: lesson) }
}

extension AcademicClient {
    /// The alternate upstream timetable reads textual lesson schedules, rather
    /// than the primary timetable's datum.scheduleList.
    func lessonScheduleCourses(semesterID: Int) async throws -> [Course] {
        let context = try await loadStudentContext()
        let termData = try await get("for-std/course-table/get-data", query: [URLQueryItem(name: "bizTypeId", value: "\(context.bizTypeID)"), URLQueryItem(name: "semesterId", value: "\(semesterID)"), URLQueryItem(name: "dataId", value: "\(context.studentID)")])
        let term = try JSONDecoder().decode(AcademicTermResponse.self, from: termData)
        var periods: [AcademicPeriodTime] = []
        if let id = term.timeTableLayoutId {
            let body = try JSONSerialization.data(withJSONObject: ["timeTableLayoutId": id])
            let data = try await request("ws/schedule-table/timetable-layout", method: "POST", body: body)
            struct Layout: Decodable { let result: Result; struct Result: Decodable { let courseUnitList: [AcademicPeriodTime] } }
            periods = try JSONDecoder().decode(Layout.self, from: data).result.courseUnitList
        }
        let courses = AcademicLessonTextParser.courses(term.lessons, periods: periods)
        if courses.isEmpty && term.lessons.contains(where: { $0.scheduleText?.isEmpty == false }) {
            throw AcademicClientError.invalidData("教务2课表的时间文字无法识别，请刷新学期数据")
        }
        return courses
    }
    static func details(for lesson: AcademicLesson) -> CourseDetails {
        CourseDetails(lessonID: Int(lesson.id), type: lesson.courseTypeName, weeksText: lesson.suggestedWeeks,
            classmatesCount: lesson.classmatesCount, credits: lesson.credits,
            teachers: lesson.teachers.map { CourseTeacher(name: $0.name) }, department: lesson.departmentName,
            examMode: lesson.examModeName, code: lesson.code, semester: lesson.semesterName,
            className: lesson.className, scheduleText: lesson.scheduleText, remark: lesson.remark)
    }
    static func detailCourse(for lesson: AcademicLesson) -> Course {
        Course(name: lesson.courseName, teacher: lesson.teachers.map(\.name).joined(separator: "、"), location: "", weekday: 1,
            startTime: "", endTime: "", colorIndex: 0, source: "academic", details: details(for: lesson))
    }
    func fetchTermCourses(semesterID: Int) async throws -> [AcademicTermCourse] {
        let context = try await loadStudentContext()
        let query = [URLQueryItem(name: "bizTypeId", value: "\(context.bizTypeID)"), URLQueryItem(name: "semesterId", value: "\(semesterID)"), URLQueryItem(name: "dataId", value: "\(context.studentID)")]
        let term = try JSONDecoder().decode(AcademicTermResponse.self, from: await get("for-std/course-table/get-data", query: query))
        var books: [String: [String: Any]] = [:]
        var notice: String?
        do {
            let data = try await get("for-std/lesson-textbook/get-data", query: query)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let map = root["textbookAssignMap"] as? [String: [String: Any]] else { throw AcademicClientError.invalidData("教材尚未公布") }
            books = map
        } catch {
            // Courses remain useful while the independent textbook service is
            // unavailable. Surface that partial state instead of an empty page.
            notice = "教材暂未获取，可下拉刷新重试"
        }
        return term.lessons.map { lesson in
            AcademicTermCourse(lesson: lesson, textbook: books[lesson.id]?["textbook"] as? String ?? "", specialTextbook: books[lesson.id]?["specialTextbook"] as? String ?? "", textbookNotice: notice)
        }
    }
}

struct AcademicPeriodTime: Decodable {
    let nameZh: String
    let startTime: Int
    let endTime: Int
    let startTimeText: String
    let endTimeText: String
}

enum AcademicLessonTextParser {
    static func courses(_ lessons: [AcademicLesson], periods: [AcademicPeriodTime]) -> [Course] {
        var output: [Course] = []
        for (color, lesson) in lessons.enumerated() {
            for (index, line) in (lesson.scheduleText ?? "").components(separatedBy: .newlines).enumerated() {
                let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
                guard tokens.count >= 3 else { continue }
                let weeks = parseWeeks(tokens[0])
                let days = ["周一": 1, "周二": 2, "周三": 3, "周四": 4, "周五": 5, "周六": 6, "周日": 7, "周天": 7]
                guard let weekday = days[tokens[1]], !weeks.isEmpty else { continue }
                let numbers = AcademicHTMLText.matches(tokens[2], "[一二三四五六七八九十百0-9]+")
                guard let first = numbers.first.flatMap({ number($0[0]) }), let last = numbers.last.flatMap({ number($0[0]) }), first > 0, last >= first else { continue }
                let actualTimes = AcademicHTMLText.matches(line, "(\\d{1,2}[:：]\\d{2})\\s*[~～至-]\\s*(\\d{1,2}[:：]\\d{2})").first
                let start = actualTimes?[1].replacingOccurrences(of: "：", with: ":") ?? (periods.indices.contains(first - 1) ? clock(periods[first - 1].startTime) : "")
                let end = actualTimes?[2].replacingOccurrences(of: "：", with: ":") ?? (periods.indices.contains(last - 1) ? clock(periods[last - 1].endTime) : "")
                guard !start.isEmpty, !end.isEmpty else { continue }
                let place = tokens.count > 4 ? tokens[4].components(separatedBy: CharacterSet(charactersIn: "(（")).first ?? "" : ""
                output.append(Course(id: ScheduleSourceParser.stableID("lesson-text|\(lesson.id)|\(index)|\(line)"), name: lesson.courseName,
                    teacher: lesson.teachers.map(\.name).joined(separator: "、"), location: place, weekday: weekday,
                    startTime: start, endTime: end, colorIndex: color % 5, weekIndices: weeks, source: "academic", details: AcademicClient.details(for: lesson)))
            }
        }
        return output
    }
    static func parseWeeks(_ text: String) -> [Int] {
        let cleaned = text.replacingOccurrences(of: "[(（][^)）]*[)）]", with: "", options: .regularExpression).replacingOccurrences(of: "周", with: "")
        return Array(Set(cleaned.replacingOccurrences(of: "，", with: ",").split(separator: ",").flatMap { part -> [Int] in
            let bounds = part.components(separatedBy: CharacterSet(charactersIn: "~～-至")).compactMap(Int.init)
            if bounds.count == 2, bounds[0] > 0, bounds[0] <= bounds[1], bounds[1] <= 100 { return Array(bounds[0]...bounds[1]) }
            if bounds.count == 1, bounds[0] > 0, bounds[0] <= 100 { return bounds }
            return []
        })).sorted()
    }
    private static func clock(_ value: Int) -> String { String(format: "%02d:%02d", value / 100, value % 100) }
    private static func number(_ text: String) -> Int? {
        if let value = Int(text) { return value }
        let digits = ["一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9, "十": 10]
        if let value = digits[text] { return value }
        if text.hasPrefix("十"), let ones = digits[String(text.dropFirst())] { return 10 + ones }
        if text.hasSuffix("十"), let tens = digits[String(text.dropLast())] { return tens * 10 }
        return nil
    }
}

extension OfficialCourseSearchResult {
    var detailCourse: Course {
        Course(name: courseName, teacher: teachers.joined(separator: "、"), location: "", weekday: 1, startTime: "", endTime: "", colorIndex: 0, source: "academic",
               details: lessonDetails ?? CourseDetails(lessonID: id, weeksText: weeks, credits: credits, teachers: teachers.map { CourseTeacher(name: $0) }, department: department, code: code, className: className, scheduleText: schedule))
    }
}

extension OfficialCampusAPIClient {
    func classroomSchedule(roomID: Int, semesterID: Int) async throws -> [Course] {
        let data = try await uniAppAuthorizedData(path: "eams-micro-server/api/v1/lesson/room/getLessons?semesterAssoc=\(semesterID)&roomAssoc=\(roomID)")
        return try ScheduleSourceParser.uniApp(data)
    }
}

enum ClassroomTimeAxis {
    static func minute(_ text: String) -> Int? {
        let fields = text.replacingOccurrences(of: "-", with: ":").split(separator: ":").compactMap { Int($0) }
        guard fields.count == 2, (0...23).contains(fields[0]), (0...59).contains(fields[1]) else { return nil }
        return fields[0] * 60 + fields[1]
    }
    static func freePeriods(_ occupations: [OfficialEmptyClassroom.Occupation], from start: Int = 480, to end: Int = 1320) -> [ClosedRange<Int>] {
        let spans = occupations.compactMap { item -> (Int, Int)? in
            guard let low = minute(item.startTimeString), let high = minute(item.endTimeString), low < high else { return nil }
            return (max(start, low), min(end, high))
        }.filter { $0.0 < $0.1 }.sorted { $0.0 < $1.0 }
        var cursor = start
        var gaps: [ClosedRange<Int>] = []
        for (low, high) in spans {
            if low > cursor { gaps.append(cursor...low) }
            cursor = max(cursor, high)
        }
        if cursor < end { gaps.append(cursor...end) }
        return gaps
    }
    static func clock(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }
}
