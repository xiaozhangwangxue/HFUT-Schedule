import XCTest
@testable import HFUTSchedule

final class FeatureCatalogTests: XCTestCase {
    func testCASEncryptionMatchesAndroidAES() throws {
        XCTAssertEqual(
            try CASLoginClient.encryptAES("password", key: "1234567890123456"),
            "mcM3yWWT+8sre6MjlFUpww=="
        )
    }

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

    func testEveryFeatureHasAnExplicitDestination() {
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

    func testAcademicScheduleAcceptsCurrentLooseFieldTypes() throws {
        let json = """
        {
          "result": {
            "lessonList": [{"id": 42, "name": "高等数学"}],
            "scheduleList": [{
              "lessonId": "42", "room": "翠十二教 101", "weekday": "1",
              "personName": null, "weekIndex": "2", "startTime": "0800",
              "endTime": 950, "date": "2026-09-21"
            }]
          }
        }
        """.data(using: .utf8)!
        let datum = try JSONDecoder().decode(AcademicDatumResponse.self, from: json)
        let payload = AcademicSyncPayload(
            term: AcademicTermResponse(lessonIds: [42], timeTableLayoutId: nil, currentWeek: nil),
            datum: datum
        )

        XCTAssertEqual(payload.courses().first?.name, "高等数学")
        XCTAssertEqual(payload.courses().first?.location, "翠十二教 101")
        XCTAssertEqual(payload.courses().first?.startTime, "08:00")
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

    func testAcademicHTMLParsersMatchAndroidFields() {
        let info = """
        <li class="list-group-item text-right">学号 <span>2026123456</span></li>
        <li class="list-group-item text-right">中文姓名 <span>测试同学</span></li>
        <dl><dt>院系</dt><dd>计算机与信息学院</dd><dt>专业</dt><dd>软件工程</dd><dt>行政班</dt><dd>软件 2601</dd></dl>
        """
        let profile = """
        <div class="list-group-item"><div class="col-md-3"><strong>邮箱</strong></div><div class="col-md-6"><span>student@example.edu.cn</span></div></div>
        """
        let student = AcademicHTMLParser.studentInfo(from: info, profileHTML: profile, fallbackStudentID: "0")

        XCTAssertEqual(student.studentID, "2026123456")
        XCTAssertEqual(student.name, "测试同学")
        XCTAssertEqual(student.department, "计算机与信息学院")
        XCTAssertEqual(student.major, "软件工程")
        XCTAssertEqual(student.className, "软件 2601")
        XCTAssertEqual(student.fields["邮箱"], "student@example.edu.cn")

        let gradesHTML = """
        <h3>2026~2027年第1学期</h3><table class="student-grade-table"><tr><td>高等数学</td><td></td><td>MATH1001</td><td>5</td><td>3.8</td><td>期末</td><td>92</td></tr></table>
        """
        XCTAssertEqual(AcademicHTMLParser.grades(from: gradesHTML).first?.grades.first?.score, "92")

        let gradesWithoutLegacyClass = """
        <h3>2026~2027年第1学期</h3><table><tr><td>大学英语</td><td></td><td>EN1001</td><td>2</td><td>3.5</td><td>期末</td><td>88</td></tr></table>
        """
        XCTAssertEqual(AcademicHTMLParser.grades(from: gradesWithoutLegacyClass).first?.grades.first?.score, "88")

        let examsHTML = """
        <table><tbody><tr><td>高等数学</td><td>2027-01-08 08:00~10:00</td><td>翠十二教 101</td></tr></tbody></table>
        """
        XCTAssertEqual(AcademicHTMLParser.exams(from: examsHTML).first?.place, "翠十二教 101")
    }
}
