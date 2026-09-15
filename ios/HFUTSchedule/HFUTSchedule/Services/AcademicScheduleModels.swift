import Foundation

struct AcademicSyncPayload: Decodable {
    let term: AcademicTermResponse
    let datum: AcademicDatumResponse
}

struct AcademicTermResponse: Decodable {
    let lessonIds: [Int]
    let timeTableLayoutId: Int
    let currentWeek: Int?
}

struct AcademicDatumResponse: Decodable {
    let result: AcademicDatum
}

struct AcademicDatum: Decodable {
    let lessonList: [AcademicLesson]
    let scheduleList: [AcademicSchedule]
}

struct AcademicLesson: Decodable {
    let courseName: String
    let id: String
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
}

struct AcademicLocalizedName: Decodable {
    let nameZh: String
}

extension AcademicSyncPayload {
    func courses() -> [Course] {
        let names = Dictionary(uniqueKeysWithValues: datum.result.lessonList.map { ($0.id, $0.courseName) })
        let grouped = Dictionary(grouping: datum.result.scheduleList) { item in
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

private struct AcademicCourseKey: Hashable {
    let lessonID: Int
    let weekday: Int
    let startTime: Int
    let endTime: Int
    let room: String
    let teacher: String
}
