import Combine
import SwiftUI
import UIKit
import XCTest
@testable import HFUTSchedule

@MainActor
final class FunctionalRepair132Tests: XCTestCase {
    private func bill(_ id: Int) -> CampusCardBill {
        .init(tranamt: 508, resume: "食堂", fromAccount: "", turnoverType: "消费", orderId: "\(id)", jndatetimeStr: "2026-11-26 12:00:00", effectdateStr: "")
    }
    func testTabSelectionAndHistoryDoNotInvalidateCampusPages() {
        let oldCampus = UserDefaults.standard.object(forKey: "selectedCampus")
        defer { UserDefaults.standard.set(oldCampus, forKey: "selectedCampus") }
        let state = AppState()
        var pageInvalidations = 0, tabInvalidations = 0
        let pages = state.objectWillChange.sink { pageInvalidations += 1 }
        let tabs = state.tabSelection.objectWillChange.sink { tabInvalidations += 1 }
        state.selectedTab = .services
        state.navigationHistory = [.init(title: "查询中心")]
        XCTAssertEqual(pageInvalidations, 0)
        XCTAssertEqual(tabInvalidations, 1)
        state.campus = state.campus == .hefei ? .xuancheng : .hefei
        XCTAssertEqual(pageInvalidations, 1, "Campus changes must still refresh service views")
        withExtendedLifetime((pages, tabs)) {}
    }
    func testFastCalendarDateParserKeepsStrictDatesAndTimeZones() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        XCTAssertNotNil(CampusDateCodec.date("2024-02-29", calendar: calendar))
        XCTAssertNil(CampusDateCodec.date("2026-02-29", calendar: calendar))
        XCTAssertNil(CampusDateCodec.date("2026-2-09", calendar: calendar))
        let local = CampusDateCodec.date("2026-11-26", calendar: calendar)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let utc = CampusDateCodec.date("2026-11-26", calendar: calendar)
        XCTAssertEqual(utc!.timeIntervalSince(local!), 8 * 3600, accuracy: 0.01)
    }
    func testShowerThousandthsAreIndependentFromCardCents() {
        XCTAssertEqual(ShowerMoney.yuan(45080), 45.08, accuracy: 0.00001)
        XCTAssertEqual(ShowerMoney.yuan("8"), 0.008, accuracy: 0.00001)
        XCTAssertEqual(bill(1).amount, 5.08, accuracy: 0.00001)
    }
    func testFocusShowsCashAndLaundryBalanceDirectlyWithoutGiftOrPhone() {
        XCTAssertEqual(PhoneFeeAmount.balance(["手机号": "13800000000", "现金金额（单位：元）": "45.08", "赠送金额（单位：元）": "10"]), "¥45.08")
        XCTAssertEqual(PhoneFeeAmount.balance(["账户余额": "18.5元", "手机号": "13800000000"]), "¥18.50")
        XCTAssertNil(PhoneFeeAmount.balance(["手机号": "13800000000"]))
    }
    func testPhoneAutofillUsesProfileAndKeepsManualOverride() {
        let info = AcademicStudentInfo(studentID: "fixture", name: "示例", fields: ["手机": "+86 138-0000-0000", "电话": "0551-12345678"])
        XCTAssertEqual(StudentPhone.from(info), "13800000000")
        XCTAssertEqual(StudentPhone.autofill("", info: info), "13800000000")
        XCTAssertEqual(StudentPhone.autofill("13900000000", info: info), "13900000000")
        XCTAssertNil(StudentPhone.normalized("138****0000"))
        XCTAssertNil(StudentPhone.normalized("0551-12345678"))
    }
    func testBillDecodeAllowsNullMetadataAndNumericStringsWithoutChangingUnits() throws {
        let data = Data(#"{"records":[{"tranamt":"4508","resume":"食堂","fromAccount":null,"turnoverType":"消费","orderId":123,"jndatetimeStr":"2026-11-26 12:00:00","effectdateStr":null}],"total":"1","size":"30"}"#.utf8)
        let page = try JSONDecoder().decode(CampusCardBillPage.self, from: data)
        XCTAssertEqual(page.records[0].amount, 45.08, accuracy: 0.00001)
        XCTAssertEqual(page.records[0].orderId, "123")
        XCTAssertEqual(page.total, 1)
        XCTAssertEqual(CampusServiceClient.huiXinAuthorization("fixture"), "bearer fixture")
        XCTAssertEqual(CampusServiceClient.huiXinAuthorization("Bearer fixture"), "Bearer fixture")
    }
    func testBillPaginationContinuesWhenServerCapsRequestedPageSize() async throws {
        var pages: [Int] = []
        let rows = try await CampusCardPagination.all { page, _ in
            pages.append(page)
            return CampusCardBillPage(records: page == 1 ? [self.bill(1), self.bill(2)] : [self.bill(3)], total: 3, size: 2)
        }
        XCTAssertEqual(pages, [1, 2]); XCTAssertEqual(rows.count, 3)
    }
    func testBillPaginationRejectsRepeatedPageRatherThanReportingPartialAnalysis() async {
        do {
            _ = try await CampusCardPagination.all { _, _ in CampusCardBillPage(records: [self.bill(1)], total: 2, size: 1) }
            XCTFail("A repeated page must not be treated as all bills")
        } catch { XCTAssertTrue(error.localizedDescription.contains("分页")) }
    }
    func testLaundryUsesOfficialPhoneFieldAndRejectsMultiSelectionForm() throws {
        let fields = try HuiXinPhoneFeeForm.fields(metadata: Data(#"{"map":{"total":[{"code":"mobileAccount","name":"手机号码","level":1}]}}"#.utf8), itemID: 26, phone: "13800000000")
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: fields)["mobileAccount"], "13800000000")
        XCTAssertNil(Dictionary(uniqueKeysWithValues: fields)["telPhone"])
        XCTAssertThrowsError(try HuiXinPhoneFeeForm.fields(metadata: Data(#"{"map":{"total":[{"code":"building"},{"code":"room"}]}}"#.utf8), itemID: 26, phone: "13800000000"))
    }
    func testBalanceCacheAndForcedRefreshAndChangingAccount() async {
        var calls = 0
        let model = PhoneFeeBalanceModel(service: .laundry) { _ in calls += 1; return ["余额": "45.08元"] }
        await model.refresh(campus: .hefei, phone: "13800000000")
        await model.refresh(campus: .hefei, phone: "13800000000")
        XCTAssertEqual(calls, 1); XCTAssertEqual(model.summary, "¥45.08")
        await model.refresh(campus: .hefei, phone: "13800000000", force: true)
        XCTAssertEqual(calls, 2)
        await model.refresh(campus: .hefei, phone: "")
        XCTAssertTrue(model.results.isEmpty); XCTAssertNotNil(model.error)
        await model.refresh(campus: .xuancheng, phone: "13800000000")
        XCTAssertEqual(calls, 2); XCTAssertTrue(model.results.isEmpty)
    }
    func testMailResponseDoesNotTreatServiceErrorAsUnactivatedMailbox() throws {
        XCTAssertNil(try CampusMailResponse.url(from: Data(#"{"msg":"success","data":null}"#.utf8)))
        XCTAssertEqual(try CampusMailResponse.url(from: Data(#"{"code":20000,"msg":"success","data":"https://mail.hfut.edu.cn/sso"}"#.utf8))?.host, "mail.hfut.edu.cn")
        XCTAssertThrowsError(try CampusMailResponse.url(from: Data(#"{"code":401,"data":null}"#.utf8)))
        XCTAssertThrowsError(try CampusMailResponse.url(from: Data(#"{"data":"javascript:alert(1)"}"#.utf8)))
    }
    func testMountedNativeStackCanOpenOwnedDestinationAndReturn() async throws {
        let coordinator = PlatformNavigationCoordinator.shared
        let scope = "regression-" + UUID().uuidString
        let appeared = expectation(description: "Destination appeared")
        let route = coordinator.register(id: UUID(), title: "个人信息") { Text("内部功能").onAppear { appeared.fulfill() } }
        let host = UIHostingController(rootView: PlatformScopeNavigationStack(scope: scope) { Text("查询中心") })
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852)); window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; coordinator.closeScope(scope, restoring: nil) }
        try await Task.sleep(for: .milliseconds(200))
        coordinator.setPath([route], scope: scope)
        await fulfillment(of: [appeared], timeout: 3)
        coordinator.setPath([], scope: scope)
        XCTAssertTrue(coordinator.paths[scope]?.isEmpty == true)
    }
    func testRouteSurvivesLinkDisappearingBeforeSwiftUICommitsPush() {
        var built = 0
        let coordinator = PlatformNavigationCoordinator()
        let id = UUID()
        let route = coordinator.register(id: id, title: "个人信息") { built += 1; return Text("内容") }
        // The source view may be gone before Native NavigationStack uses it.
        // Route ownership must be sufficient with no source-link lifecycle.
        _ = coordinator.destination(for: route)
        XCTAssertEqual(built, 1, "The transaction must not show 页面已失效")
        coordinator.setPath([route], scope: "services")
        _ = coordinator.destination(for: route)
        XCTAssertEqual(built, 2)
        coordinator.setPath([], scope: "services")
        _ = coordinator.destination(for: route)
        XCTAssertEqual(built, 3, "Interactive pop still owns its outgoing route")
    }
    func testLazyDestinationsAndIndependentNavigationPaths() {
        var constructed = 0
        let coordinator = PlatformNavigationCoordinator()
        let route = coordinator.register(id: UUID(), title: "示例") { constructed += 1; return Text("子页面") }
        XCTAssertEqual(constructed, 0)
        let inactive = coordinator.pathState(for: "schedule")
        var invalidations = 0
        let observation = inactive.objectWillChange.sink { invalidations += 1 }
        coordinator.setPath([route], scope: "services")
        XCTAssertEqual(invalidations, 0)
        _ = coordinator.destination(for: route)
        XCTAssertEqual(constructed, 1)
        _ = SourceAnchoredNavigationLink(sourceID: "fixture") { constructed += 1; return Text("destination") } label: { Text("打开") }
        XCTAssertEqual(constructed, 1)
        withExtendedLifetime(observation) {}
    }
    func testSelectionNullableOptionalTurnFieldsAndStringIDs() throws {
        let turns = try JSONDecoder().decode([AcademicCourseSelectionTurn].self, from: Data(#"[{"id":"42","name":"通识选课","bulletin":null,"selectDateTimeText":null,"addRulesText":null}]"#.utf8))
        XCTAssertEqual(turns.first?.id, 42)
        XCTAssertEqual(turns.first?.addRulesText, [])
        let lessons = try AcademicClient.parseSelectionLessons(Data(#"[{"id":"17","code":"A001","course":{"nameZh":"程序设计"},"teachers":[],"limitCount":30}]"#.utf8))
        XCTAssertEqual(lessons.first?.id, 17)
    }
    func testWebNavigationNormalizesInputAndRejectsNonWebSchemes() {
        XCTAssertEqual(WebNavigationURL.normalized("hfut.edu.cn")?.scheme, "https")
        XCTAssertEqual(WebNavigationURL.normalized(" HTTPS://www.hfut.edu.cn ")?.host, "www.hfut.edu.cn")
        XCTAssertNil(WebNavigationURL.normalized("https://"))
        XCTAssertNil(WebNavigationURL.normalized("ftp://hfut.edu.cn"))
    }
    func testLongActivityTitleLayoutAtCompactAndLargeWidths() throws {
        let start = Date(), end = start.addingTimeInterval(7200)
        let state = CourseActivityAttributes.ContentState(title: "大学计算机程序设计与算法基础期末考试", location: "翡翠湖校区综合教学楼 2 号楼 301 教室", start: start, end: end, kind: "exam")
        for width: CGFloat in [288, 360] {
            let view = CourseActivityExpandedContent(state: state, previewProgress: 0.3).padding(.horizontal, 16).padding(.bottom, 12)
                .frame(width: width).background(.black).foregroundStyle(.white).preferredColorScheme(.dark)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertLessThan(image.size.height, 180)
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Preview132-Island-\(Int(width)).png")
            try XCTUnwrap(image.pngData()).write(to: url)
            let attachment = XCTAttachment(image: image); attachment.name = "Activity \(width)"; attachment.lifetime = .keepAlways; add(attachment)
        }
    }
    func testTextbookFailureDoesNotHideTermCoursesThroughActualTransport() async throws {
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [Repair132URLProtocol.self]
        let client = AcademicClient(mode: .direct, cookies: [], configuration: configuration)
        let rows = try await client.fetchTermCourses(semesterID: 354)
        XCTAssertEqual(rows.first?.lesson.courseName, "程序设计")
        XCTAssertNotNil(rows.first?.textbookNotice)
    }
}

private final class Repair132URLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path
        var status = 200, headers: [String: String] = [:], body = ""
        if path.hasSuffix("course-table") { status = 302; headers["Location"] = "/eams5-student/for-std/course-table/info/123" }
        else if path.hasSuffix("info/123") { body = "<script>var context = {bizTypeId: 1}</script>" }
        else if path.contains("lesson-textbook") { status = 503; body = "unavailable" }
        else { body = #"{"lessonIds":[1],"lessons":[{"id":1,"course":{"nameZh":"程序设计"},"teacherAssignmentList":[]}]}"# }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
