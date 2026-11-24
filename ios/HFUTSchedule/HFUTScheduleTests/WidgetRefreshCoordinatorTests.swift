import XCTest
import Security
@testable import HFUTSchedule

@MainActor
final class WidgetRefreshCoordinatorTests: XCTestCase {
    private func status(_ revision: UUID = UUID(), success: Bool = true) -> WidgetPublicationStatus {
        .init(revision: revision, publishedAt: .now, courseCount: 1,
              appGroupWritten: false, keychainStatus: success ? errSecSuccess : errSecMissingEntitlement)
    }

    func testEverySuccessfulRequestReloadsImmediatelyEvenWithPreviousAcknowledgement() {
        let publication = status()
        var count = 0
        let coordinator = WidgetRefreshCoordinator(publication: { publication }, acknowledged: { _ in true },
                                                   reload: { count += 1 })
        coordinator.requestReload()
        coordinator.requestReload()
        XCTAssertEqual(count, 2)
    }

    func testFailedWriteDoesNotRequestReload() {
        let publication = status(success: false)
        var count = 0
        let coordinator = WidgetRefreshCoordinator(publication: { publication }, acknowledged: { _ in false },
                                                   reload: { count += 1 })
        coordinator.requestReload()
        coordinator.requestPendingReload()
        XCTAssertEqual(count, 0)
    }

    func testMissingReceiptHasOnlyThreeBoundedRetries() async throws {
        let publication = status()
        var count = 0
        let coordinator = WidgetRefreshCoordinator(publication: { publication }, acknowledged: { _ in false },
                                                   reload: { count += 1 }, sleep: { _ in })
        coordinator.requestReload()
        try await waitUntil { count == 4 }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(count, 4)
    }

    func testReceiptStopsRetryBeforeAnotherReload() async throws {
        let publication = status()
        let gate = SleepGate()
        var count = 0
        var read = false
        let coordinator = WidgetRefreshCoordinator(publication: { publication }, acknowledged: { _ in read },
                                                   reload: { count += 1 }, sleep: { _ in await gate.pause() })
        coordinator.requestReload()
        try await gate.waitForPause()
        read = true
        await gate.resume()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(count, 1)
    }

    func testOldRevisionCannotRetryAfterNewPublication() async throws {
        var publication = status()
        let gate = SleepGate()
        var count = 0
        let coordinator = WidgetRefreshCoordinator(publication: { publication }, acknowledged: { _ in false },
                                                   reload: { count += 1 }, sleep: { _ in await gate.pause() })
        coordinator.requestReload()
        try await gate.waitForPause()
        publication = status()
        await gate.resume()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(count, 1)
    }

    func testHomeScreenHandoffReloadsOnlyPendingPublication() {
        let publication = status()
        var count = 0
        var read = false
        let coordinator = WidgetRefreshCoordinator(publication: { publication }, acknowledged: { _ in read },
                                                   reload: { count += 1 })
        coordinator.requestPendingReload()
        XCTAssertEqual(count, 1)
        read = true
        coordinator.requestPendingReload()
        XCTAssertEqual(count, 1)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition() && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(2)) }
        XCTAssertTrue(condition())
    }

    private actor SleepGate {
        private var continuation: CheckedContinuation<Void, Never>?
        func pause() async { await withCheckedContinuation { continuation = $0 } }
        func waitForPause() async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(2))
            while continuation == nil && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(2)) }
            XCTAssertNotNil(continuation)
        }
        func resume() { continuation?.resume(); continuation = nil }
    }
}
