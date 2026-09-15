import Foundation

struct AcademicSyncPayload: Decodable {
    let term: AcademicTermResponse
    let datum: AcademicDatumResponse
}

struct AcademicTermResponse: Decodable {
    let lessonIds: [Int]
    let timeTableLayoutId: Int?
    let currentWeek: Int?

    init(lessonIds: [Int], timeTableLayoutId: Int?, currentWeek: Int?) {
        self.lessonIds = lessonIds
        self.timeTableLayoutId = timeTableLayoutId
        self.currentWeek = currentWeek
    }

    private enum CodingKeys: String, CodingKey {
        case lessonIds, timeTableLayoutId, currentWeek
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if let integers = try? values.decode([Int].self, forKey: .lessonIds) {
            lessonIds = integers
        } else {
            lessonIds = try values.decode([String].self, forKey: .lessonIds).compactMap(Int.init)
        }
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

    init(courseName: String, id: String) {
        self.courseName = courseName
        self.id = id
    }

    private enum CodingKeys: String, CodingKey { case courseName, name, id }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        courseName = (try? values.decode(String.self, forKey: .courseName))
            ?? (try? values.decode(String.self, forKey: .name))
            ?? ""
        id = values.flexibleString(forKey: .id) ?? ""
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
        let names = Dictionary(uniqueKeysWithValues: datum.result.lessonList.map { ($0.id, $0.courseName) })
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
            Course(
                name: names[String(key.lessonID)] ?? String(key.lessonID),
                teacher: key.teacher,
                location: key.room,
                weekday: key.weekday,
                startTime: Self.format(time: key.startTime),
                endTime: Self.format(time: key.endTime),
                colorIndex: abs(key.lessonID) % 5,
                weekIndices: Array(Set(schedules.map(\.weekIndex))).sorted(),
                dates: Array(Set(schedules.map(\.date))).sorted(),
                source: "academic"
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
