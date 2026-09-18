import Foundation

struct AcademicSyncPayload: Decodable {
    let term: AcademicTermResponse
    let datum: AcademicDatumResponse
}

struct AcademicTermResponse: Decodable {
    let lessonIds: [Int]
    let lessons: [AcademicLesson]
    let timeTableLayoutId: Int?
    let currentWeek: Int?

    init(lessonIds: [Int], lessons: [AcademicLesson] = [], timeTableLayoutId: Int?, currentWeek: Int?) {
        self.lessonIds = lessonIds
        self.lessons = lessons
        self.timeTableLayoutId = timeTableLayoutId
        self.currentWeek = currentWeek
    }

    private enum CodingKeys: String, CodingKey {
        case lessonIds, lessons, timeTableLayoutId, currentWeek
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if let integers = try? values.decode([Int].self, forKey: .lessonIds) {
            lessonIds = integers
        } else {
            lessonIds = try values.decode([String].self, forKey: .lessonIds).compactMap(Int.init)
        }
        lessons = ((try? values.decode([LossyValue<AcademicLesson>].self, forKey: .lessons)) ?? []).compactMap(\.value)
        timeTableLayoutId = values.flexibleInt(forKey: .timeTableLayoutId)
        currentWeek = values.flexibleInt(forKey: .currentWeek)
    }
}

struct AcademicDatumResponse: Decodable {
    let result: AcademicDatum
}

struct AcademicDatum: Decodable {
    let lessonList: [AcademicLesson]
    let scheduleList: [AcademicSchedule]

    init(lessonList: [AcademicLesson], scheduleList: [AcademicSchedule]) {
        self.lessonList = lessonList
        self.scheduleList = scheduleList
    }

    private enum CodingKeys: String, CodingKey { case lessonList, scheduleList }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        lessonList = ((try? values.decode([LossyValue<AcademicLesson>].self, forKey: .lessonList)) ?? []).compactMap(\.value)
        scheduleList = ((try? values.decode([LossyValue<AcademicSchedule>].self, forKey: .scheduleList)) ?? []).compactMap(\.value)
    }
}

struct AcademicLesson: Decodable {
    let courseName: String
    let id: String
    let className: String?
    let remark: String?
    let suggestedWeeks: String?
    let courseTypeName: String?
    let classmatesCount: Int?
    let credits: Double?
    let teachers: [AcademicTeacherAssignment]
    let departmentName: String?
    let examModeName: String?
    let code: String?
    let semesterName: String?
    let scheduleText: String?

    init(courseName: String, id: String) {
        self.courseName = courseName
        self.id = id
        className = nil
        remark = nil
        suggestedWeeks = nil
        courseTypeName = nil
        classmatesCount = nil
        credits = nil
        teachers = []
        departmentName = nil
        examModeName = nil
        code = nil
        semesterName = nil
        scheduleText = nil
    }

    private enum CodingKeys: String, CodingKey {
        case courseName, name, nameZh, id, remark, suggestScheduleWeekInfo, courseTypeName
        case stdCount, course, courseType, openDepartment, examMode, scheduleWeeksInfo
        case teacherAssignmentList, semester, code, scheduleText
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let course = try? values.decode(AcademicCourseInfo.self, forKey: .course)
        courseName = (try? values.decode(String.self, forKey: .courseName))
            ?? (try? values.decode(String.self, forKey: .name))
            ?? course?.nameZh
            ?? ""
        id = values.flexibleString(forKey: .id) ?? ""
        className = values.flexibleString(forKey: .nameZh)
        remark = values.flexibleString(forKey: .remark)
        suggestedWeeks = values.flexibleString(forKey: .scheduleWeeksInfo)
            ?? values.flexibleString(forKey: .suggestScheduleWeekInfo)
        courseTypeName = (try? values.decode(AcademicLocalizedName.self, forKey: .courseType))?.nameZh
            ?? values.flexibleString(forKey: .courseTypeName)
        classmatesCount = values.flexibleInt(forKey: .stdCount)
        credits = course?.credits
        teachers = ((try? values.decode([LossyValue<AcademicTeacherAssignment>].self, forKey: .teacherAssignmentList)) ?? []).compactMap(\.value)
        departmentName = (try? values.decode(AcademicLocalizedName.self, forKey: .openDepartment))?.nameZh
        examModeName = (try? values.decode(AcademicLocalizedName.self, forKey: .examMode))?.nameZh
        code = values.flexibleString(forKey: .code) ?? course?.code
        semesterName = (try? values.decode(AcademicSemester.self, forKey: .semester))?.nameZh
        scheduleText = (try? values.decode(AcademicScheduleText.self, forKey: .scheduleText))?.text
    }
}

struct AcademicTeacherAssignment: Decodable {
    let name: String
    let age: Int?
    let title: String?
    let type: String?

    private enum CodingKeys: String, CodingKey { case name, age, titleName, person, teacher }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let person = try? values.decode(AcademicLocalizedName.self, forKey: .person)
        let teacher = try? values.decode(AcademicTeacherInfo.self, forKey: .teacher)
        name = person?.nameZh
            ?? values.flexibleString(forKey: .name)
            ?? teacher?.person?.nameZh
            ?? ""
        age = values.flexibleInt(forKey: .age)
        title = values.flexibleString(forKey: .titleName) ?? teacher?.title?.nameZh
        type = teacher?.type?.nameZh
    }
}

private struct AcademicCourseInfo: Decodable {
    let nameZh: String?
    let credits: Double?
    let code: String?

    private enum CodingKeys: String, CodingKey { case nameZh, credits, code }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        nameZh = values.flexibleString(forKey: .nameZh)
        if let value = try? values.decodeIfPresent(Double.self, forKey: .credits) {
            credits = value
        } else if let value = values.flexibleString(forKey: .credits) {
            credits = Double(value)
        } else {
            credits = nil
        }
        code = values.flexibleString(forKey: .code)
    }
}

private struct AcademicTeacherInfo: Decodable {
    let person: AcademicLocalizedName?
    let title: AcademicLocalizedName?
    let type: AcademicLocalizedName?
}

private struct AcademicSemester: Decodable {
    let nameZh: String?
}

private struct AcademicScheduleText: Decodable {
    let text: String?

    private enum CodingKeys: String, CodingKey { case dateTimePlacePersonText }
    private enum TextCodingKeys: String, CodingKey { case textZh }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard let nested = try? values.nestedContainer(keyedBy: TextCodingKeys.self, forKey: .dateTimePlacePersonText) else {
            text = nil
            return
        }
        text = try? nested.decodeIfPresent(String.self, forKey: .textZh)
    }
}

struct AcademicSchedule: Decodable {
    let lessonId: Int
    let room: AcademicLocalizedName?
    let weekday: Int
    let personName: String
    let weekIndex: Int
    let startTime: Int
    let endTime: Int
    let date: String

    init(
        lessonId: Int, room: AcademicLocalizedName?, weekday: Int, personName: String,
        weekIndex: Int, startTime: Int, endTime: Int, date: String
    ) {
        self.lessonId = lessonId
        self.room = room
        self.weekday = weekday
        self.personName = personName
        self.weekIndex = weekIndex
        self.startTime = startTime
        self.endTime = endTime
        self.date = date
    }

    private enum CodingKeys: String, CodingKey {
        case lessonId, room, weekday, personName, weekIndex, startTime, endTime, date
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        lessonId = values.flexibleInt(forKey: .lessonId) ?? 0
        room = try? values.decodeIfPresent(AcademicLocalizedName.self, forKey: .room)
        weekday = values.flexibleInt(forKey: .weekday) ?? 0
        personName = values.flexibleString(forKey: .personName) ?? ""
        weekIndex = values.flexibleInt(forKey: .weekIndex) ?? 0
        startTime = values.flexibleInt(forKey: .startTime) ?? 0
        endTime = values.flexibleInt(forKey: .endTime) ?? 0
        date = values.flexibleString(forKey: .date) ?? ""
    }
}

struct AcademicLocalizedName: Decodable {
    let nameZh: String

    init(nameZh: String) {
        self.nameZh = nameZh
    }

    private enum CodingKeys: String, CodingKey { case nameZh, name }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let value = try? single.decode(String.self) {
            nameZh = value
            return
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        nameZh = (try? values.decode(String.self, forKey: .nameZh))
            ?? (try? values.decode(String.self, forKey: .name))
            ?? ""
    }
}

extension AcademicSyncPayload {
    func courses() -> [Course] {
        let names = Dictionary(datum.result.lessonList.map { ($0.id, $0.courseName) }, uniquingKeysWith: { first, _ in first })
        let termLessons = Dictionary(term.lessons.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let datumLessons = Dictionary(datum.result.lessonList.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let validSchedules = datum.result.scheduleList.filter {
            $0.lessonId > 0 && (1...7).contains($0.weekday) && $0.weekIndex > 0 && $0.startTime > 0 && $0.endTime > 0
        }
        let grouped = Dictionary(grouping: validSchedules) { item in
            AcademicCourseKey(
                lessonID: item.lessonId,
                weekday: item.weekday,
                startTime: item.startTime,
                endTime: item.endTime,
                room: item.room?.nameZh.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                teacher: item.personName.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return grouped.map { key, schedules in
            let lesson = termLessons[String(key.lessonID)] ?? datumLessons[String(key.lessonID)]
            return Course(
                name: lesson?.courseName.nonEmpty ?? names[String(key.lessonID)]?.nonEmpty ?? String(key.lessonID),
                teacher: key.teacher,
                location: key.room,
                weekday: key.weekday,
                startTime: Self.format(time: key.startTime),
                endTime: Self.format(time: key.endTime),
                colorIndex: abs(key.lessonID) % 5,
                weekIndices: Array(Set(schedules.map(\.weekIndex))).sorted(),
                dates: Array(Set(schedules.map(\.date))).sorted(),
                source: "academic",
                details: CourseDetails(
                    lessonID: key.lessonID,
                    type: lesson?.courseTypeName?.nonEmpty,
                    weeksText: lesson?.suggestedWeeks?.nonEmpty,
                    classmatesCount: lesson?.classmatesCount,
                    credits: lesson?.credits,
                    teachers: lesson?.teachers.compactMap { teacher -> CourseTeacher? in
                        guard let name = teacher.name.nonEmpty else { return nil }
                        return CourseTeacher(name: name, age: teacher.age, title: teacher.title?.nonEmpty, type: teacher.type?.nonEmpty)
                    } ?? [],
                    department: lesson?.departmentName?.nonEmpty,
                    examMode: lesson?.examModeName?.nonEmpty,
                    code: lesson?.code?.nonEmpty,
                    semester: lesson?.semesterName?.nonEmpty,
                    className: lesson?.className?.nonEmpty,
                    scheduleText: lesson?.scheduleText?.nonEmpty,
                    remark: lesson?.remark?.nonEmpty
                )
            )
        }
        .sorted {
            if $0.weekday == $1.weekday { return $0.startTime < $1.startTime }
            return $0.weekday < $1.weekday
        }
    }

    private static func format(time: Int) -> String {
        let hour = time / 100
        let minute = time % 100
        return String(format: "%02d:%02d", hour, minute)
    }
}

private extension String {
    var nonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private extension KeyedDecodingContainer {
    func flexibleInt(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return Int(value) }
        if let value = try? decodeIfPresent(String.self, forKey: key) { return Int(value) }
        return nil
    }

    func flexibleString(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return String(value) }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return String(value) }
        return nil
    }
}

private struct LossyValue<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

private struct AcademicCourseKey: Hashable {
    let lessonID: Int
    let weekday: Int
    let startTime: Int
    let endTime: Int
    let room: String
    let teacher: String
}
