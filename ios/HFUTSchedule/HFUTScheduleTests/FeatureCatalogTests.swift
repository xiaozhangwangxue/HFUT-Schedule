import XCTest
@testable import HFUTSchedule

final class FeatureCatalogTests: XCTestCase {
    func testFeatureIDsAreUnique() {
        let ids = FeatureCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testCatalogMatchesAndroidSurface() {
        XCTAssertEqual(FeatureCatalog.all.count, 48)
        XCTAssertTrue(FeatureCategory.allCases.allSatisfy { category in
            FeatureCatalog.all.contains { $0.category == category }
        })
    }

    func testEveryFeatureHasAUsableDestination() {
        let unavailable = FeatureCatalog.all.filter {
            $0.url == nil && $0.nativeDestination == nil
        }
        XCTAssertEqual(unavailable.map(\.title), ["AI 助手"])
    }

    func testCourseWeekdayNames() {
        XCTAssertEqual(Course.preview.first?.weekdayName, "周二")
    }

    func testAcademicSchedulePayloadGroupsWeeksAndFormatsTime() {
        let payload = AcademicSyncPayload(
            term: AcademicTermResponse(lessonIds: [42], timeTableLayoutId: 1, currentWeek: 3),
            datum: AcademicDatumResponse(
                result: AcademicDatum(
                    lessonList: [AcademicLesson(courseName: "数据结构", id: "42")],
                    scheduleList: [
                        AcademicSchedule(
                            lessonId: 42,
                            room: AcademicLocalizedName(nameZh: " 翡翠科教楼 A101 "),
                            weekday: 3,
                            personName: " 张老师 ",
                            weekIndex: 2,
                            startTime: 800,
                            endTime: 940,
                            date: "2026-09-16"
                        ),
                        AcademicSchedule(
                            lessonId: 42,
                            room: AcademicLocalizedName(nameZh: " 翡翠科教楼 A101 "),
                            weekday: 3,
                            personName: " 张老师 ",
                            weekIndex: 4,
                            startTime: 800,
                            endTime: 940,
                            date: "2026-09-30"
                        )
                    ]
                )
            )
        )

        let courses = payload.courses()

        XCTAssertEqual(courses.count, 1)
        XCTAssertEqual(courses[0].name, "数据结构")
        XCTAssertEqual(courses[0].teacher, "张老师")
        XCTAssertEqual(courses[0].location, "翡翠科教楼 A101")
        XCTAssertEqual(courses[0].weekday, 3)
        XCTAssertEqual(courses[0].startTime, "08:00")
        XCTAssertEqual(courses[0].endTime, "09:40")
        XCTAssertEqual(courses[0].weekIndices, [2, 4])
        XCTAssertEqual(courses[0].dates, ["2026-09-16", "2026-09-30"])
        XCTAssertEqual(courses[0].source, "academic")
    }

    func testLegacyCourseBackupStillDecodes() throws {
        let json = """
        [{
          "id": "9F2365E8-3A80-4D30-99F1-72E76565E16A",
          "name": "大学英语",
          "teacher": "",
          "location": "教学楼 B305",
          "weekday": 2,
          "startTime": "14:00",
          "endTime": "15:40",
          "colorIndex": 1
        }]
        """.data(using: .utf8)!

        let courses = try JSONDecoder().decode([Course].self, from: json)

        XCTAssertEqual(courses.count, 1)
        XCTAssertNil(courses[0].weekIndices)
        XCTAssertNil(courses[0].dates)
        XCTAssertNil(courses[0].source)
    }

    func testAcademicRecordsPayloadDecodes() throws {
        let json = """
        {
          "grades": [{
            "term": "2026-2027 学年第一学期",
            "grades": [{
              "courseName": "高等数学",
              "credits": "5",
              "gpa": "3.8",
              "score": "92",
              "detail": "期末考试 92",
              "lessonCode": "MATH1001"
            }]
          }],
          "exams": [{
            "name": "高等数学",
            "dateTime": "2027-01-08 08:00~10:00",
            "place": "翠十二教 101"
          }]
        }
        """.data(using: .utf8)!

        let payload = try JSONDecoder().decode(AcademicRecordsPayload.self, from: json)

        XCTAssertEqual(payload.grades.first?.grades.first?.score, "92")
        XCTAssertEqual(payload.exams.first?.place, "翠十二教 101")
        XCTAssertNotNil(payload.exams.first?.startDate)
    }
}
