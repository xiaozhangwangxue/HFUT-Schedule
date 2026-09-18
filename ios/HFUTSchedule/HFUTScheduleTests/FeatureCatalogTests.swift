import XCTest
@testable import HFUTSchedule

final class FeatureCatalogTests: XCTestCase {
    @MainActor
    func testDeepLinksOpenOriginalMainSections() {
        let state = AppState()

        state.open(URL(string: "hfut-schedule://schedule")!)
        XCTAssertEqual(state.selectedTab, .schedule)

        state.open(URL(string: "hfut-schedule://focus")!)
        XCTAssertEqual(state.selectedTab, .home)

        state.open(URL(string: "hfut-schedule://services")!)
        XCTAssertEqual(state.selectedTab, .services)

        state.open(URL(string: "hfut-schedule://options")!)
        XCTAssertEqual(state.selectedTab, .me)

        state.open(URL(string: "hfut-schedule://options?mode=webvpn&login=1")!)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "academicConnectionMode"), AcademicConnectionMode.webVPN.rawValue)
        XCTAssertTrue(state.consumeLoginRequest())
        XCTAssertFalse(state.consumeLoginRequest())
        UserDefaults.standard.removeObject(forKey: "academicConnectionMode")

        state.open(URL(string: "hfut-schedule://services?feature=8")!)
        XCTAssertEqual(state.selectedTab, .services)
        XCTAssertEqual(state.consumePendingFeature()?.title, "挂科率")
    }

    func testOfficialAPIModelsDecodeAndroidEndpointPayloads() throws {
        let classmatesJSON = """
        {"data":[{"code":"2026123456","nameZh":"测试同学","adminclass":"软件2601","gender":"男","telephone":null}]}
        """.data(using: .utf8)!
        struct ClassmateEnvelope: Decodable { let data: [OfficialClassmate] }
        let classmate = try XCTUnwrap(JSONDecoder().decode(ClassmateEnvelope.self, from: classmatesJSON).data.first)
        XCTAssertEqual(classmate.className, "软件2601")

        let failRateJSON = """
        {"courseName":"高等数学","courseMetaId":"MATH1001","courseFailRateDTOList":[{"xn":"2026-2027","xq":"1","avgScore":78.5,"totalCount":100,"failCount":8,"successRate":0.92}]}
        """.data(using: .utf8)!
        let failRate = try JSONDecoder().decode(OfficialFailRateRecord.self, from: failRateJSON)
        XCTAssertEqual(failRate.terms.first?.failCount, 8)
        XCTAssertEqual(failRate.terms.first?.successRate, 0.92)
    }

    func testRequestedCampusServicesUseOriginalNativeFlows() {
        let expected: [Int: NativeDestination] = [
            1: .campusCard,
            3: .electricity,
            4: .campusNetwork,
            5: .campusMail,
            7: .grades,
            8: .failRate,
            12: .bathing,
            9: .courseSummary,
            11: .webNavigation,
            14: .dormitory,
            18: .program,
            19: .library,
            24: .classrooms,
            26: .workRest,
            28: .campusLife,
            29: .transferMajor,
            31: .teacherSearch,
            32: .fee,
            35: .todayCampus,
            38: .holidays,
            40: .laundry,
            44: .huiXin,
            45: .secondClass,
            49: .express
        ]
        for (id, destination) in expected {
            XCTAssertEqual(FeatureCatalog.all.first(where: { $0.id == id })?.nativeDestination, destination)
        }
    }

    func testUniAppDefaultPasswordUsesIdentitySuffixAndXRule() {
        XCTAssertEqual(
            OfficialCampusAPIClient.defaultUniAppPassword(identityNumber: "340100200001021234"),
            "Hfut@#$%021234"
        )
        XCTAssertEqual(
            OfficialCampusAPIClient.defaultUniAppPassword(identityNumber: "34010020000102123X"),
            "Hfut@#$%102123"
        )
    }

    func testOriginalExternalServiceRoutesArePreserved() {
        XCTAssertTrue(CampusServiceClient.alipayCampusCardURL.absoluteString.contains("_4kQhV32216tp7bzlDc3E1k"))
        XCTAssertTrue(CampusServiceClient.pinduoduoExpressURL.absoluteString.contains("identificationCode"))
        XCTAssertTrue(CampusServiceClient.taobaoExpressURL.absoluteString.contains("identity-code"))
    }

    func testLifeServiceModelsDecodeAndroidPayloads() throws {
        let laundryJSON = """
        {"data":{"items":[{"id":1,"name":"一号洗衣房","address":"一号楼","workTime":"06:00-23:00","categoryCodeList":["00"],"enableReserve":true,"reserveNum":2,"idleCount":3}]}}
        """.data(using: .utf8)!
        struct LaundryTestEnvelope: Decodable {
            let data: DataValue
            struct DataValue: Decodable { let items: [LaundryLocation] }
        }
        let laundry = try XCTUnwrap(JSONDecoder().decode(LaundryTestEnvelope.self, from: laundryJSON).data.items.first)
        XCTAssertEqual(laundry.idleCount, 3)

        let secondClassJSON = """
        {"id":"42","name":"志愿活动","module":"志愿服务","sponsor":"校团委","peopleNum":100,"beginTime":"2026-09-16 08:00","endTime":"2026-09-16 10:00","activePhoto":"/a.jpg","form":"线下","campus":1,"keynoteSpeaker":null,"theVenue":"大学生活动中心"}
        """.data(using: .utf8)!
        let activity = try JSONDecoder().decode(SecondClassActivity.self, from: secondClassJSON)
        XCTAssertEqual(activity.sponsor, "校团委")
    }

    func testCASEncryptionMatchesAndroidAES() throws {
        XCTAssertEqual(
            try CASLoginClient.encryptAES("password", key: "1234567890123456"),
            "mcM3yWWT+8sre6MjlFUpww=="
        )
    }

    func testWebVPNConversionMatchesAndroidConverter() {
        let direct = URL(string: "http://jxglstu.hfut.edu.cn/eams5-student/")!
        XCTAssertEqual(
            WebVPNURLConverter.convert(direct)?.absoluteString,
            AcademicPortal.webVPNAcademicRoot.absoluteString
        )
    }

    func testDirectAcademicRoutesUseCurrentSecureOfficialOrigin() {
        XCTAssertEqual(AcademicPortal.directAcademicRoot.scheme, "https")
        XCTAssertEqual(
            CASLoginClient.service,
            "http://jxglstu.hfut.edu.cn/eams5-student/neusoft-sso/login"
        )
        XCTAssertFalse(FeatureCatalog.all.contains { feature in
            feature.url?.host == "jxglstu.hfut.edu.cn" && feature.url?.scheme == "http"
        })
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

    func testAcademicSchedulePreservesOriginalCourseDetails() throws {
        let termJSON = """
        {
          "lessonIds": [42], "timeTableLayoutId": 1, "currentWeek": 2,
          "lessons": [{
            "id": 42, "nameZh": "自动化26-1班", "remark": "课堂要求",
            "scheduleWeeksInfo": "2~17周", "stdCount": 186,
            "course": {"nameZh": "高等数学A（上）", "credits": 6.0, "code": "1400211B"},
            "courseType": {"nameZh": "通识必修课"},
            "openDepartment": {"nameZh": "数学学院"},
            "examMode": {"nameZh": "考试"},
            "code": "1400211B-028",
            "semester": {"nameZh": "2026-2027学年第一学期"},
            "teacherAssignmentList": [{
              "person": {"nameZh": "李慧民"}, "age": 45,
              "teacher": {"title": {"nameZh": "教授"}, "type": {"nameZh": "专任教师"}}
            }],
            "scheduleText": {"dateTimePlacePersonText": {"textZh": "2~17周 周一 第一节~第二节 翠五教304"}}
          }]
        }
        """.data(using: .utf8)!
        let term = try JSONDecoder().decode(AcademicTermResponse.self, from: termJSON)
        let payload = AcademicSyncPayload(
            term: term,
            datum: AcademicDatumResponse(result: AcademicDatum(
                lessonList: [AcademicLesson(courseName: "高等数学A（上）", id: "42")],
                scheduleList: [AcademicSchedule(
                    lessonId: 42, room: AcademicLocalizedName(nameZh: "翠五教304"), weekday: 1,
                    personName: "李慧民", weekIndex: 2, startTime: 800, endTime: 940, date: "2026-09-14"
                )]
            ))
        )

        let details = try XCTUnwrap(payload.courses().first?.details)
        XCTAssertEqual(details.type, "通识必修课")
        XCTAssertEqual(details.classmatesCount, 186)
        XCTAssertEqual(details.credits, 6.0)
        XCTAssertEqual(details.teachers.first?.name, "李慧民")
        XCTAssertEqual(details.department, "数学学院")
        XCTAssertEqual(details.code, "1400211B-028")
        XCTAssertEqual(details.className, "自动化26-1班")
        XCTAssertEqual(details.scheduleText, "2~17周 周一 第一节~第二节 翠五教304")
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
        <li class="list-group-item text-right">证件号 <span>34010120010123456X</span></li>
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
        XCTAssertEqual(student.fields["证件号"], "34010120010123456X")
        XCTAssertEqual(
            OfficialCampusAPIClient.defaultUniAppPassword(identityNumber: student.fields["证件号"] ?? ""),
            "Hfut@#$%123456"
        )

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

    func testLibraryDiscoveryResultAllowsElectronicBookWithoutAuthor() throws {
        let json = """
        {
          "title": "<span class='keywords'>高等数学</span>",
          "publishers": "合肥工业大学出版社",
          "year": 2024,
          "abstract": "教材简介",
          "isbn": "978-7-5650-6406-7",
          "click": 30,
          "ds": [{"tName": "电子图书"}],
          "gc": [{"cp": "电子仓储", "in": "O13"}]
        }
        """.data(using: .utf8)!

        let book = try JSONDecoder().decode(OfficialLibraryBook.self, from: json)

        XCTAssertEqual(book.author, [])
        XCTAssertEqual(book.ds?.first?.tName, "电子图书")
        XCTAssertEqual(book.gc?.first?.cp, "电子仓储")
    }

    func testLaundryDeviceStillDecodesWhenLiveAPILeavesOutReserveCount() throws {
        let json = """
        {
          "id": 287337,
          "name": "2楼01号洗衣机",
          "floorCode": "2",
          "state": 1,
          "finishTime": null,
          "enableReserve": true
        }
        """.data(using: .utf8)!

        let device = try JSONDecoder().decode(LaundryDevice.self, from: json)

        XCTAssertEqual(device.id, 287337)
        XCTAssertEqual(device.floorText, "2 楼")
        XCTAssertEqual(device.stateText, "空闲")
        XCTAssertEqual(device.reserveNum, 0)
    }

    func testLaundryDeviceUsesFinishTimeAsOccupiedAndShowsRemainingTime() throws {
        let json = """
        {
          "id": 287338,
          "name": "2楼02号洗衣机",
          "floorCode": "2",
          "state": 3,
          "finishTime": "2099-09-17 09:30:00",
          "enableReserve": false
        }
        """.data(using: .utf8)!

        let device = try JSONDecoder().decode(LaundryDevice.self, from: json)

        XCTAssertEqual(device.stateText, "占用")
        XCTAssertNotNil(device.finishDate)
        XCTAssertTrue(device.remainingUsageText?.hasPrefix("预计剩余 ") == true)
    }

    func testLaundryDeviceReportsStateThreeWithoutFinishTimeAsOffline() throws {
        let json = """
        {
          "id": 287339,
          "name": "2楼03号洗衣机",
          "floorCode": "2",
          "state": 3,
          "finishTime": null,
          "enableReserve": false
        }
        """.data(using: .utf8)!

        let device = try JSONDecoder().decode(LaundryDevice.self, from: json)

        XCTAssertEqual(device.stateText, "离线/故障")
        XCTAssertNil(device.remainingUsageText)
    }

    func testAppointmentMatchesAndroidDevelopingDestination() throws {
        let feature = try XCTUnwrap(FeatureCatalog.all.first { $0.id == 46 })
        XCTAssertEqual(feature.nativeDestination, .appointment)
        XCTAssertNil(feature.url)
    }

    func testClassroomRequestsMatchAndroidRetrofitShape() throws {
        XCTAssertEqual(
            OfficialCampusAPIClient.buildingsURL.absoluteString,
            "https://jwglapp.hfut.edu.cn/eams-micro-server/api/v1/room/place/building?campusAssoc="
        )

        let data = try OfficialCampusAPIClient.emptyClassroomRequestBody(
            date: "2026-09-17",
            campusID: 3,
            buildingIDs: [],
            floors: []
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["campusAssoc"] as? Int, 3)
        XCTAssertEqual(json["buildingIds"] as? [Int], [])
        XCTAssertEqual(json["floors"] as? [Int], [])
        XCTAssertEqual(json["pageSize"] as? Int, 30)
    }

    func testRepairUsesAndroidStyleNativeCampusChooser() throws {
        let feature = try XCTUnwrap(FeatureCatalog.all.first { $0.id == 21 })
        XCTAssertEqual(feature.nativeDestination, .repair)
        XCTAssertNil(feature.url)
    }
}
