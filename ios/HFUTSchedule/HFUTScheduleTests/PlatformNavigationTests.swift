import SwiftUI
import XCTest
@testable import HFUTSchedule

@MainActor
final class PlatformNavigationTests: XCTestCase {
    private func route(_ title: String) -> PlatformNavigationRoute { PlatformNavigationRoute(id: UUID(), title: title) }

    func testReturnToAncestorRemovesOnlyLaterRoutesInSameTab() {
        let coordinator = PlatformNavigationCoordinator()
        let first = route("校园卡"), second = route("付款码"), other = route("课程详情")
        coordinator.activate("services")
        coordinator.setPath([first, second], scope: "services")
        coordinator.setPath([other], scope: "schedule")
        coordinator.returnTo(first.id)
        XCTAssertEqual(coordinator.paths["services"], [first])
        XCTAssertEqual(coordinator.paths["schedule"], [other])
    }
    func testReturnToRootKeepsRootIdentityAndClearsActualPath() {
        let coordinator = PlatformNavigationCoordinator()
        coordinator.activate("home")
        let root = coordinator.history(forScope: "home")[0]
        coordinator.setPath([route("课程详情")], scope: "home")
        coordinator.returnTo(root.id)
        XCTAssertEqual(coordinator.paths["home"], [])
        XCTAssertEqual(coordinator.history(forScope: "home")[0].id, root.id)
    }
    func testLaunchpadCanReturnUnderlyingScopeWhileItsOwnModalIsActive() {
        let coordinator = PlatformNavigationCoordinator()
        let first = route("图书馆"), second = route("借阅记录")
        coordinator.activate("services")
        coordinator.setPath([first, second], scope: "services")
        coordinator.activate("modal-fixture", title: "启动台")
        coordinator.returnTo(first.id, in: "services")
        XCTAssertEqual(coordinator.paths["services"], [first])
        XCTAssertEqual(coordinator.activeScope, "modal-fixture")
        coordinator.deactivate("modal-fixture", restoring: "services")
        XCTAssertEqual(coordinator.activeScope, "services")
    }
    func testUnknownReturnIsIgnoredAndNavigationBindingWritesSamePath() {
        let coordinator = PlatformNavigationCoordinator()
        let first = route("课程详情")
        coordinator.activate("schedule")
        let binding = coordinator.binding(for: .schedule)
        binding.wrappedValue = [first]
        coordinator.returnTo(UUID())
        XCTAssertEqual(binding.wrappedValue, [first])
    }
    func testClosingLocalScopePreservesOtherTabPaths() {
        let coordinator = PlatformNavigationCoordinator()
        let item = route("课程详情")
        coordinator.setPath([item], scope: "schedule")
        coordinator.activate("modal-fixture", title: "编辑日程")
        coordinator.setPath([route("教学楼")], scope: "modal-fixture")
        coordinator.closeScope("modal-fixture", restoring: "schedule")
        XCTAssertNil(coordinator.paths["modal-fixture"])
        XCTAssertEqual(coordinator.paths["schedule"], [item])
        XCTAssertEqual(coordinator.activeScope, "schedule")
    }
    func testDiagnosticsRedactsBearerPasswordAndQueryTokens() {
        let text = PlatformDiagnosticRedactor.redact("Authorization: Bearer fixture-secret password=sample token=public ticket=private-value https://user:secret@example.com/")
        XCTAssertFalse(text.contains("fixture-secret"))
        XCTAssertFalse(text.contains("password=sample"))
        XCTAssertFalse(text.contains("private-value"))
        XCTAssertFalse(text.contains("user:secret"))
    }
    func testDiagnosticsRetainsOnlyLatestThirtyAndCanClear() {
        let store = PlatformDiagnosticsStore()
        for index in 0..<35 { store.record(context: "离线测试 \(index)", error: NSError(domain: "Fixture", code: index)) }
        XCTAssertEqual(store.reports.count, 30)
        XCTAssertEqual(store.reports.first?.context, "离线测试 34")
        store.clear()
        XCTAssertTrue(store.reports.isEmpty)
    }
    func testDiagnosticsDoesNotStoreServerBodiesOrURLQuerySecrets() {
        XCTAssertTrue(PlatformDiagnosticRedactor.safeMessage(#"{"token":"private-value","records":[1,2]}"#).contains("原始响应未记录"))
        XCTAssertTrue(PlatformDiagnosticRedactor.safeMessage("<html><body>private-response</body></html>").contains("原始响应未记录"))
        let value = PlatformDiagnosticRedactor.safeMessage("请求失败 https://example.com/path?unknown_secret=private-value")
        XCTAssertFalse(value.contains("private-value"))
        XCTAssertFalse(value.contains("/path"))
        XCTAssertTrue(PlatformDiagnosticRedactor.safeMessage(String(repeating: "x", count: 601)).contains("原始响应未记录"))
    }
    func testForegroundActivityTimerUsesUpcomingThresholdAndEndBoundaries() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let item = PlatformScheduleOccurrence(id: "fixture", sourceID: UUID().uuidString, kind: .course,
            title: "测试", location: "", detail: "", start: now.addingTimeInterval(930), end: now.addingTimeInterval(1200))
        XCTAssertEqual(CourseLiveActivityManager.nextForegroundRefresh([item], now: now), now.addingTimeInterval(30))
        let beforeStart = item.start.addingTimeInterval(-10)
        XCTAssertEqual(CourseLiveActivityManager.nextForegroundRefresh([item], now: beforeStart), item.start)
        let beforeEnd = item.end.addingTimeInterval(-10)
        XCTAssertEqual(CourseLiveActivityManager.nextForegroundRefresh([item], now: beforeEnd), item.end)
        XCTAssertEqual(CourseLiveActivityManager.nextForegroundRefresh([], now: now), now.addingTimeInterval(60))
    }
}
