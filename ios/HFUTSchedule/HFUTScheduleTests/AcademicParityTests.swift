import XCTest
@testable import HFUTSchedule

final class AcademicParityTests: XCTestCase {
    @MainActor
    func testGradeUnreadBaselineSurvivesRelaunchAndRepeatedSync() throws {
        let suite = "AcademicParityTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = AcademicGrade(courseName: "示例一", credits: "2", gpa: "3", score: "80", detail: "", lessonCode: "FIXTURE-1")
        let second = AcademicGrade(courseName: "示例二", credits: "3", gpa: "4", score: "90", detail: "", lessonCode: "FIXTURE-2")
        let initial = [AcademicGradeTerm(term: "测试学期", grades: [first])]
        let updated = [AcademicGradeTerm(term: "测试学期", grades: [first, second])]
        let store = AcademicRecordsStore(defaults: defaults)
        store.markGradesRead() // An empty first visit must not create an empty baseline.
        store.replaceGrades(with: initial)
        XCTAssertEqual(store.newGradeCount, 0)
        store.replaceGrades(with: updated)
        XCTAssertEqual(store.newGradeCount, 1)
        store.replaceGrades(with: updated)
        XCTAssertEqual(store.newGradeCount, 1)
        let reopened = AcademicRecordsStore(defaults: defaults)
        XCTAssertEqual(reopened.newGradeCount, 1)
        reopened.markGradesRead()
        XCTAssertEqual(AcademicRecordsStore(defaults: defaults).newGradeCount, 0)
    }

    func testSelectionParserRetainsUnscheduledCourse() throws {
        let json = #"[{"id":123,"code":"FIXTURE","course":{"nameZh":"未排课示例"},"teachers":[],"limitCount":20,"dateTimePlace":{"textZh":""}}]"#
        let lessons = try AcademicClient.parseSelectionLessons(Data(json.utf8))
        XCTAssertEqual(lessons.count, 1)
        XCTAssertEqual(lessons.first?.id, 123)
        XCTAssertEqual(lessons.first?.schedule, "")
    }

    func testFailedSchoolSubmissionPreservesSchoolMessage() throws {
        let selection = try AcademicClient.parseSubmission(Data(#"{"success":false,"errorMessage":{"textZh":"选课人数已满"}}"#.utf8))
        XCTAssertFalse(selection.success)
        XCTAssertEqual(selection.message, "选课人数已满")
        let transfer = try AcademicClient.parseSubmission(Data(#"{"result":false,"errors":[{"textZh":"申请时间已结束"}]}"#.utf8))
        XCTAssertFalse(transfer.success)
        XCTAssertEqual(transfer.message, "申请时间已结束")
    }

    func testTransferDetailsParseNestedArrangementsAndScores() {
        let html = """
        <div class="interview-arrange-1"><table><tr><td>面试安排</td><td><span>时间</span><span>测试时间</span></td><td>测试地点</td></tr></table></div>
        <div class="score-box"><span>GPA</span><span class="score-text">3.5</span><span class="score-rank">排名 <span>12</span></span></div>
        """
        let fields = AcademicClient.parseTransferDetails(html)
        XCTAssertTrue(fields.contains { $0.label == "面试安排" && $0.value.contains("测试时间") && $0.value.contains("测试地点") })
        XCTAssertTrue(fields.contains { $0.label == "GPA" && $0.value.contains("3.5") && $0.value.contains("12") })
    }

    func testProgramProgressRetainsOutsideAndUnrepairedCourses() throws {
        let json = #"{"moduleList":[],"outerCourseList":[{"code":"OUTSIDE","nameZh":"方案外示例","credits":2,"terms":[],"compulsory":false,"resultType":"UNREPAIRED","score":null,"rank":null,"gp":null}]}"#
        let progress = try JSONDecoder().decode(ProgramProgressDetails.self, from: Data(json.utf8))
        XCTAssertEqual(progress.outerCourseList.first?.status, "未修")
        XCTAssertEqual(progress.outerCourseList.first?.code, "OUTSIDE")
    }

    func testCardForecastUsesYuanAndExcludesElectricityAndRecharges() {
        func bill(_ day: String, _ cents: Int, merchant: String = "测试餐厅", type: String = "消费") -> CampusCardBill {
            CampusCardBill(tranamt: cents, resume: merchant, fromAccount: "fixture", turnoverType: type, orderId: day + merchant + type, jndatetimeStr: day + " 12:00:00", effectdateStr: day)
        }
        let result = CampusCardAnalysis.forecast([bill("2026-01-01", 1000), bill("2026-01-02", 2000), bill("2026-01-03", 3000), bill("2026-01-03", 90000, merchant: "宿舍电费"), bill("2026-01-03", 50000, type: "充值")])
        XCTAssertEqual(result.dailyAverage, 20, accuracy: 0.001)
        XCTAssertEqual(result.nextDay ?? -1, 40, accuracy: 0.001)
        XCTAssertEqual(result.dailyR2 ?? -1, 1, accuracy: 0.001)
        XCTAssertEqual(result.monthlyAmounts["2026-01"], 60)
        XCTAssertEqual(result.merchants["测试餐厅"], 60)
        XCTAssertNil(result.nextMonth)
    }

    func testInsufficientForecastDoesNotReturnNaN() {
        XCTAssertNil(CampusCardAnalysis.linearForecast([(0, 12)]))
        XCTAssertNil(CampusCardAnalysis.linearForecast([(0, 12), (0, 13)]))
        let constant = CampusCardAnalysis.linearForecast([(0, 12), (1, 12)])
        XCTAssertEqual(constant?.0, 12)
        XCTAssertEqual(constant?.1, 1)
    }

    func testGatewayUnitsAndHistoricalRecordsMatchSchoolFields() throws {
        let status = try SchoolNetworkClient.parseStatus("var flow='1048576 '; var fee='125000 ';", gateway: "fixture")
        XCTAssertEqual(status.usedMB, 1024)
        XCTAssertEqual(status.fee, 12.5)
        let html = "<table id='example'><tbody><tr><td>2026-09-01</td><td>2026-09-30</td><td>测试套餐</td><td>10</td><td>2.5</td><td>120</td><td>2048</td><td>2026-10-01</td></tr></tbody></table>"
        let history = try SchoolNetworkClient.parseHistory(html)
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.flowMB, 2048)
        XCTAssertEqual(history.first?.durationMinutes, 120)
        XCTAssertThrowsError(try SchoolNetworkClient.parseHistory("<form id='loginform'></form>"))
    }

    func testHefeiNetworkAndCardDefaultPasswordRulesDifferForX() throws {
        let suite = "AcademicParityCredentials.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let info = AcademicStudentInfo(studentID: "FIXTURE", name: "测试", fields: ["证件号": "11000020000101234X"])
        defaults.set(try JSONEncoder().encode(info), forKey: "academicStudentInfo")
        XCTAssertEqual(try LifeCredentialPolicy.cardCredentials(defaults: defaults).password, "101234")
        XCTAssertEqual(try LifeCredentialPolicy.networkCredentials(xuancheng: false, defaults: defaults).password, "01234X")
        XCTAssertEqual(try LifeCredentialPolicy.networkCredentials(xuancheng: true, defaults: defaults).password, "101234")
    }

    func testMalformedTransferListCannotConfirmCancellation() throws {
        for invalid in [#"{"message":"登录失效"}"#, #"{"models":[{"id":"invalid","changeMajorSubmit":{}}]}"#, #"{"models":[{"id":9}]}"#] {
            XCTAssertThrowsError(try AcademicClient.parseMyTransferApplications(Data(invalid.utf8)))
        }
        let empty = try AcademicClient.parseMyTransferApplications(Data(#"{"models":[]}"#.utf8))
        XCTAssertTrue(empty.isEmpty)
        XCTAssertNoThrow(try AcademicClient.requireTransferCancelled(applicationID: 9, applications: empty))
    }

    func testCancellationChecksTheActualApplicationID() {
        let retained = TransferMyApply(id: 9, major: "测试专业", department: "测试院系", status: "PENDING")
        XCTAssertThrowsError(try AcademicClient.requireTransferCancelled(applicationID: 9, applications: [retained]))
        XCTAssertNoThrow(try AcademicClient.requireTransferCancelled(applicationID: 10, applications: [retained]))
    }

    func testSurveyHTTPAcceptanceIsNotBusinessConfirmation() {
        func lesson(_ id: Int, submitted: Bool) -> AcademicSurveyLesson {
            AcademicSurveyLesson(code: "FIXTURE", courseName: "测试课程", department: "测试院系", deadline: nil,
                teachers: [.init(id: id, name: "测试教师", submitted: submitted)])
        }
        XCTAssertThrowsError(try AcademicClient.requireSurveySubmitted(taskID: 9, lessons: []))
        XCTAssertThrowsError(try AcademicClient.requireSurveySubmitted(taskID: 9, lessons: [lesson(9, submitted: false)]))
        XCTAssertThrowsError(try AcademicClient.requireSurveySubmitted(taskID: 9, lessons: [lesson(10, submitted: true)]))
        XCTAssertNoThrow(try AcademicClient.requireSurveySubmitted(taskID: 9, lessons: [lesson(9, submitted: true)]))
    }

    func testShowerQRExtractsOnlyValidVendorMAC() {
        XCTAssertEqual(ShowerDeviceCode.fromQRCode("KLCXKJ-Water,fixture,001122aabbcc"), "001122AABBCC")
        XCTAssertEqual(ShowerDeviceCode.normalized("00:11:22:aa:bb:cc"), "001122AABBCC")
        XCTAssertNil(ShowerDeviceCode.fromQRCode("OTHER,fixture,001122AABBCC"))
        XCTAssertNil(ShowerDeviceCode.fromQRCode("KLCXKJ-Water,fixture"))
        XCTAssertNil(ShowerDeviceCode.normalized("001122AABBCG"))
        XCTAssertNil(ShowerDeviceCode.normalized("001122"))
    }

    func testBulkSurveyUsesActualHighestOptionNameAndAllBlankIDs() throws {
        let json = #"{"lessonSurveyLesson":{"surveyAssoc":1},"survey":{"radioQuestions":[{"id":"Q1","title":"测试题","options":[{"name":"中","score":3},{"name":"高","score":5},{"name":"低","score":1}]}],"blankQuestions":[{"id":"B1","title":"评价"},{"id":"B2","title":"意见"}]}}"#
        let form = try JSONDecoder().decode(AcademicSurveyForm.self, from: Data(json.utf8))
        let draft = try AcademicSurveyDraft.highest(form: form, comment: "测试评价")
        XCTAssertEqual(draft.choices, ["Q1": "高"])
        XCTAssertEqual(draft.comments, ["B1": "测试评价", "B2": "测试评价"])
        let noOptions = try JSONDecoder().decode(AcademicSurveyForm.self, from: Data(json.replacingOccurrences(of: #"[{"name":"中","score":3},{"name":"高","score":5},{"name":"低","score":1}]"#, with: "[]").utf8))
        XCTAssertThrowsError(try AcademicSurveyDraft.highest(form: noOptions, comment: ""))
    }

    func testBulkSurveyDoesNotCallMixedOrEmptyResultsComplete() {
        var confirmed = AcademicBulkSurveyResult(id: 1, teacher: "测试教师一", course: "测试课程")
        confirmed.status = .confirmed
        var uncertain = AcademicBulkSurveyResult(id: 2, teacher: "测试教师二", course: "测试课程")
        uncertain.status = .unconfirmed
        XCTAssertTrue(AcademicBulkSurveyResult.allConfirmed([confirmed]))
        XCTAssertFalse(AcademicBulkSurveyResult.allConfirmed([confirmed, uncertain]))
        XCTAssertFalse(AcademicBulkSurveyResult.allConfirmed([]))
    }
}
