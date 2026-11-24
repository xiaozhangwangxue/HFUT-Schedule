import CoreImage
import UIKit
import XCTest
@testable import HFUTSchedule

final class PlatformScannerWidgetTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return value
    }
    private func date(_ day: String, hour: Int = 0) -> Date {
        calendar.date(byAdding: .hour, value: hour, to: PlatformScheduleResolver.date(day, calendar: calendar)!)!
    }
    private func item(_ id: String, day: String = "2026-11-24", hour: Int, end: Int, kind: String = "course") -> FocusWidgetItem {
        FocusWidgetItem(id: id, title: id, location: "示例教室", start: date(day, hour: hour), end: date(day, hour: end), kind: kind, route: "hfut-schedule://home")
    }
    private func snapshot(_ items: [FocusWidgetItem], finished: Bool = true, tomorrow: Bool = true) -> FocusWidgetSnapshot {
        FocusWidgetSnapshot(revision: UUID(), updatedAt: date("2026-11-24"), items: items, fontScale: 1,
            showFinished: finished, switchesToTomorrow: tomorrow)
    }

    func testWiFiEscapedFieldsAndOpenNetworks() {
        XCTAssertEqual(ScannedWiFi.parse(#"WIFI:T:WPA;S:Example\;Lab;P:p\:a\\ss\;word;;"#),
                       ScannedWiFi(name: "Example;Lab", password: "p:a\\ss;word"))
        XCTAssertEqual(ScannedWiFi.parse("WIFI:T:nopass;S:OpenNet;;")?.password, "")
        XCTAssertNil(ScannedWiFi.parse("WIFI:P:missing-name;;"))
    }
    func testOnlySafeWebLinksAndExactCASPath() {
        XCTAssertNotNil(ScannerService.webURL("https://news.hfut.edu.cn/info/1.htm"))
        XCTAssertNil(ScannerService.webURL("javascript:alert(1)"))
        XCTAssertNil(ScannerService.webURL("https://name:password@example.com"))
        XCTAssertNotNil(ScannerService.casURL("https://cas.hfut.edu.cn/cas/app/scanQrCodeLogin?uuid=fixture"))
        XCTAssertNil(ScannerService.casURL("https://example.com/prefix/cas/app/scanQrCodeLogin?uuid=fixture"))
        XCTAssertNil(ScannerService.casURL("https://cas.hfut.edu.cn/cas/app/scanQrCodeLogin"))
    }
    func testImageQRCodeRecognitionUsesOfflineSyntheticImage() async throws {
        let generator = try XCTUnwrap(CIFilter(name: "CIQRCodeGenerator"))
        generator.setValue(Data("hfut-scanner-offline-fixture".utf8), forKey: "inputMessage")
        let output = try XCTUnwrap(generator.outputImage).transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let image = try XCTUnwrap(CIContext(options: [.useSoftwareRenderer: true]).createCGImage(output, from: output.extent))
        let data = try XCTUnwrap(UIImage(cgImage: image).pngData())
        let decoded = try await ScannerService.decodeImage(data)
        XCTAssertEqual(decoded, ["hfut-scanner-offline-fixture"])
    }
    func testMalformedPhotoReportsReadableErrorWithoutPretendingNoCodes() async {
        do { _ = try await ScannerService.decodeImage(Data("not-an-image".utf8)); XCTFail("Malformed image accepted") }
        catch { XCTAssertEqual((error as? ScannerImageRecognitionError)?.localizedDescription, ScannerImageRecognitionError.invalidImage.localizedDescription) }
    }
    func testFocusSwitchesAtLastClassEndAndHonorsPreference() {
        let value = snapshot([item("today", hour: 8, end: 10), item("tomorrow", day: "2026-11-25", hour: 8, end: 10)])
        XCTAssertFalse(FocusWidgetProjection.day(value, now: date("2026-11-24", hour: 9), calendar: calendar).isTomorrow)
        let projected = FocusWidgetProjection.day(value, now: date("2026-11-24", hour: 10), calendar: calendar)
        XCTAssertTrue(projected.isTomorrow)
        XCTAssertEqual(projected.items.map(\.id), ["tomorrow"])
        XCTAssertFalse(FocusWidgetProjection.day(snapshot(value.items, tomorrow: false), now: date("2026-11-24", hour: 10), calendar: calendar).isTomorrow)
    }
    func testFocusFiltersFinishedOnlyAfterSelectingDay() {
        let value = snapshot([item("first", hour: 8, end: 10), item("later", hour: 14, end: 16)], finished: false)
        let projected = FocusWidgetProjection.day(value, now: date("2026-11-24", hour: 12), calendar: calendar)
        XCTAssertFalse(projected.isTomorrow)
        XCTAssertEqual(projected.items.map(\.id), ["later"])
    }
    func testFocusTimelineIncludesBoundariesAndMidnightWithoutDuplicates() {
        let value = snapshot([item("first", hour: 8, end: 10), item("same", hour: 8, end: 10)])
        let now = date("2026-11-24", hour: 7)
        let dates = FocusWidgetProjection.refreshDates(value, now: now, calendar: calendar)
        XCTAssertEqual(dates, [now, date("2026-11-24", hour: 8), date("2026-11-24", hour: 10), date("2026-11-25")])
    }
    func testLiveActivityPrefersOngoingAndSkipsExpiredAndDeadlines() {
        let now = date("2026-11-24", hour: 9)
        func occurrence(_ id: String, start: Date, end: Date, kind: PlatformScheduleOccurrence.Kind = .course) -> PlatformScheduleOccurrence {
            PlatformScheduleOccurrence(id: id, sourceID: UUID().uuidString, kind: kind, title: id, location: "", detail: "", start: start, end: end)
        }
        let ongoing = occurrence("ongoing", start: now.addingTimeInterval(-600), end: now.addingTimeInterval(600))
        let soon = occurrence("soon", start: now.addingTimeInterval(300), end: now.addingTimeInterval(3000))
        let expired = occurrence("expired", start: now.addingTimeInterval(-2000), end: now)
        let deadline = occurrence("deadline", start: now.addingTimeInterval(-600), end: now.addingTimeInterval(600), kind: .deadline)
        XCTAssertEqual(CourseLiveActivityManager.currentOrSoon([soon, expired, deadline, ongoing], now: now)?.id, ongoing.id)
        XCTAssertNil(CourseLiveActivityManager.currentOrSoon([expired, deadline], now: now))
    }
    func testDeepLinkParametersAndInactiveTODOExclusions() throws {
        let normalized = try XCTUnwrap(PlatformDeepLinkURL.url(from: "hfut_schedule://news?keyword=%E8%80%83%E8%AF%95&keyword=second"))
        XCTAssertEqual(normalized.scheme, "hfut-schedule")
        let route = PlatformDeepLinkRequest(url: normalized)
        XCTAssertEqual(route?.arguments["keyword"], "考试")
        XCTAssertNotNil(PlatformDeepLinkRequest(rawValue: "hfut-schedule://home?page=CALENDAR"))
        XCTAssertNil(PlatformDeepLinkRequest(rawValue: "hfut_schedule://survey"))
        XCTAssertNil(PlatformDeepLinkRequest(rawValue: "hfut_schedule://transfer_major"))
        XCTAssertNil(PlatformDeepLinkRequest(rawValue: "https://news?keyword=test"))
    }
    func testClassmateDeepLinkRequiresPositiveBoundedID() throws {
        let normalized = try XCTUnwrap(PlatformDeepLinkURL.url(from: "hfut_schedule://course_classmates?lesson_id=123"))
        XCTAssertEqual(PlatformDeepLinkRequest(url: normalized)?.lessonID, 123)
        XCTAssertNil(PlatformDeepLinkRequest(rawValue: "hfut_schedule://course_classmates?lesson_id=-1")?.lessonID)
        XCTAssertNil(PlatformDeepLinkRequest(rawValue: "hfut_schedule://course_classmates?lesson_id=999999999999")?.lessonID)
    }
    @MainActor func testQuickActionSelectionIsDeduplicatedCappedAndIndependent() {
        let suite = "PlatformShortcutsTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["scanner", "scanner", "unknown", "payCode", "recharge", "library", "services"], forKey: HomeScreenShortcutStore.storageKey)
        XCTAssertEqual(HomeScreenShortcutStore.selected(defaults: defaults), [.scanner, .payCode, .recharge, .library])
        defaults.set([], forKey: HomeScreenShortcutStore.storageKey)
        XCTAssertTrue(HomeScreenShortcutStore.selected(defaults: defaults).isEmpty)
        for target in CampusShortcutTarget.allCases {
            let parts = URLComponents(url: target.url, resolvingAgainstBaseURL: false)
            XCTAssertEqual(parts?.queryItems?.first?.value, target.rawValue)
        }
    }
    func testNewsSearchRequestEncodesBase64AndPage() {
        let request = PlatformNewsSearchClient.request(keyword: "考试&安排", page: 3)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.host, "news.hfut.edu.cn")
        let body = String(data: request.httpBody!, encoding: .utf8)!
        XCTAssertTrue(body.contains("currentnum=3"))
        let encoded = body.components(separatedBy: "&")[0].dropFirst("sitenewskeycode=".count)
        XCTAssertEqual(Data(base64Encoded: String(encoded).removingPercentEncoding!)?.base64EncodedString(), Data("考试&安排".utf8).base64EncodedString())
    }
    func testNewsParserRejectsNonSchoolLinksAndDeduplicates() {
        let html = #"<ul><li><a href="https://jwc.hfut.edu.cn/info/1.htm" title="考试安排">标题</a><span>2026-11-24</span></li><li><a href="https://jwc.hfut.edu.cn/info/1.htm">重复</a></li><li><a href="javascript:alert(1)">脚本</a></li><li><a href="https://example.com/">非学校链接</a></li></ul>"#
        let results = PlatformNewsSearchClient.parse(html)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].title, "考试安排")
        XCTAssertEqual(results[0].date, "2026-11-24")
    }
}
