import XCTest
import Security
@testable import HFUTSchedule

final class WidgetSnapshotBridgeTests: XCTestCase {
    private final class MemoryStorage {
        var groupData: Data?
        var keychain: [String: Data] = [:]
        var receipts: [String: Data] = [:]
        var bundled: Data? = Data("[]".utf8)
        var groupWritable = false
        var keychainStatus: Int32 = errSecSuccess
        var publication: WidgetPublicationStatus?
        var documents: Data?

        func transport(group: String = "NEWPREFIX.shared") -> WidgetSnapshotTransport {
            WidgetSnapshotTransport(readAppGroup: { self.groupData }, writeAppGroup: { data in
                guard self.groupWritable else { return false }
                self.groupData = data; return true
            }, readKeychain: { self.keychain[group] }, writeKeychain: { data in
                guard self.keychainStatus == errSecSuccess else { return self.keychainStatus }
                self.keychain[group] = data; return errSecSuccess
            }, readBundle: { self.bundled }, readReceipt: { self.receipts[group] },
            writeReceipt: { self.receipts[group] = $0 }, recordPublication: { self.publication = $0 },
            writeDocumentsCopy: { self.documents = $0 })
        }
    }

    private func course() -> WidgetCourseSnapshot {
        WidgetCourseSnapshot(id: UUID(), name: "合成测试课程", teacher: "", location: "测试教室",
            weekday: 1, startTime: "08:00", endTime: "09:40", colorIndex: 0,
            weekIndices: [1], dates: ["2026-11-16"])
    }

    func testSharedChannelWorksAfterChangingSigningPrefix() throws {
        let memory = MemoryStorage()
        let app = memory.transport(group: "DIFFERENTPREFIX.common")
        let widget = memory.transport(group: "DIFFERENTPREFIX.common")
        let courses = [course()]
        XCTAssertTrue(WidgetSnapshotStore.store(courses, transport: app))
        let publication = try XCTUnwrap(memory.publication)
        XCTAssertFalse(WidgetSnapshotStore.acknowledged(publication, transport: app))
        let result = WidgetSnapshotStore.loadResult(acknowledge: true, transport: widget)
        XCTAssertEqual(result.snapshot?.courses, courses)
        XCTAssertTrue(result.hasScheduleData)
        XCTAssertTrue(WidgetSnapshotStore.acknowledged(publication, transport: app))
    }

    func testPrivateSigningGroupsCannotProduceFalseReadAcknowledgement() throws {
        let memory = MemoryStorage()
        let app = memory.transport(group: "NEWPREFIX.app")
        let widget = memory.transport(group: "NEWPREFIX.widget")
        XCTAssertTrue(WidgetSnapshotStore.store([course()], transport: app))
        let result = WidgetSnapshotStore.loadResult(acknowledge: true, transport: widget)
        XCTAssertFalse(result.hasScheduleData)
        XCTAssertFalse(WidgetSnapshotStore.acknowledged(try XCTUnwrap(memory.publication), transport: app))
    }

    func testExplicitEmptySharedScheduleNeverFallsBackToOldBundledCourses() {
        let memory = MemoryStorage()
        memory.bundled = WidgetSnapshotStore.encode([course()])
        XCTAssertTrue(WidgetSnapshotStore.store([], transport: memory.transport()))
        let result = WidgetSnapshotStore.loadResult(transport: memory.transport())
        XCTAssertEqual(result.source, .keychain)
        XCTAssertEqual(result.snapshot?.courses, [])
        XCTAssertTrue(result.hasScheduleData)
    }

    func testNewestSharedChannelWinsEvenWhenItIsEmpty() throws {
        let memory = MemoryStorage()
        let old = WidgetScheduleSnapshot(revision: UUID(), updatedAt: Date(timeIntervalSince1970: 10), termStart: nil, courses: [course()])
        memory.groupData = try JSONEncoder().encode(old)
        XCTAssertTrue(WidgetSnapshotStore.store([], transport: memory.transport(), now: Date(timeIntervalSince1970: 20)))
        XCTAssertEqual(WidgetSnapshotStore.loadResult(transport: memory.transport()).snapshot?.courses, [])
    }

    func testCorruptAppGroupDataFallsBackToValidKeychain() {
        let memory = MemoryStorage()
        memory.groupData = Data("invalid fixture".utf8)
        let courses = [course()]
        XCTAssertTrue(WidgetSnapshotStore.store(courses, transport: memory.transport()))
        XCTAssertEqual(WidgetSnapshotStore.loadResult(transport: memory.transport()).snapshot?.courses, courses)
    }

    func testClockRollbackAndPartialWriteStillChooseNewContent() throws {
        let memory = MemoryStorage()
        memory.groupWritable = true
        XCTAssertTrue(WidgetSnapshotStore.store([course()], transport: memory.transport(), now: Date(timeIntervalSince1970: 100)))
        memory.groupWritable = false
        XCTAssertTrue(WidgetSnapshotStore.store([], transport: memory.transport(), now: Date(timeIntervalSince1970: 50)))
        let result = WidgetSnapshotStore.loadResult(transport: memory.transport())
        XCTAssertEqual(result.source, .keychain)
        XCTAssertEqual(result.snapshot?.courses, [])
        XCTAssertGreaterThan(try XCTUnwrap(result.snapshot?.updatedAt), Date(timeIntervalSince1970: 100))
    }

    func testEqualTimestampsAndPartialWriteStillChooseNewContent() {
        let memory = MemoryStorage()
        memory.groupWritable = true
        let now = Date(timeIntervalSince1970: 100)
        XCTAssertTrue(WidgetSnapshotStore.store([course()], transport: memory.transport(), now: now))
        memory.groupWritable = false
        XCTAssertTrue(WidgetSnapshotStore.store([], transport: memory.transport(), now: now))
        XCTAssertEqual(WidgetSnapshotStore.loadResult(transport: memory.transport()).snapshot?.courses, [])
    }

    func testReceiptOrderingSurvivesFutureTimestampOnOlderReceipt() throws {
        let memory = MemoryStorage()
        let transport = memory.transport()
        let future = Date().addingTimeInterval(86_400)
        memory.receipts["NEWPREFIX.shared"] = try JSONEncoder().encode(WidgetSnapshotReceipt(revision: UUID(), readAt: future))
        XCTAssertTrue(WidgetSnapshotStore.store([course()], transport: transport))
        _ = WidgetSnapshotStore.loadResult(acknowledge: true, transport: transport)
        let receipt = try JSONDecoder().decode(WidgetSnapshotReceipt.self, from: XCTUnwrap(memory.receipts["NEWPREFIX.shared"]))
        XCTAssertGreaterThan(receipt.readAt, future)
        XCTAssertTrue(WidgetSnapshotStore.acknowledged(try XCTUnwrap(memory.publication), transport: transport))
    }

    func testUnavailableSharedWritesAreNotReportedSuccessfulBecauseOfDocumentsCopy() {
        let memory = MemoryStorage()
        memory.keychainStatus = errSecMissingEntitlement
        XCTAssertFalse(WidgetSnapshotStore.store([course()], transport: memory.transport()))
        XCTAssertNotNil(memory.documents)
        XCTAssertFalse(memory.publication?.didWrite ?? true)
        XCTAssertEqual(memory.publication?.keychainStatus, errSecMissingEntitlement)
    }

    func testLockedKeychainDoesNotEraseItsPreviousSnapshot() {
        let memory = MemoryStorage()
        let courses = [course()]
        XCTAssertTrue(WidgetSnapshotStore.store(courses, transport: memory.transport()))
        let previous = memory.keychain
        memory.keychainStatus = errSecInteractionNotAllowed
        XCTAssertFalse(WidgetSnapshotStore.store([], transport: memory.transport()))
        XCTAssertEqual(memory.keychain, previous)
    }

    func testAppGroupCanPublishWhenKeychainIsUnavailable() {
        let memory = MemoryStorage()
        memory.groupWritable = true
        memory.keychainStatus = errSecMissingEntitlement
        XCTAssertTrue(WidgetSnapshotStore.store([course()], transport: memory.transport()))
        XCTAssertEqual(WidgetSnapshotStore.loadResult(transport: memory.transport()).source, .appGroup)
    }

    func testManualTermStartIsIncludedInSharedPayload() {
        let memory = MemoryStorage()
        let start = Date(timeIntervalSince1970: 1_799_020_800)
        XCTAssertTrue(WidgetSnapshotStore.store([course()], termStart: start, transport: memory.transport()))
        XCTAssertEqual(WidgetSnapshotStore.loadSnapshot(transport: memory.transport())?.termStart, start)
    }

    func testLegacyArrayCanBeReadAndUpgradedToVersionedPayload() throws {
        let memory = MemoryStorage()
        let courses = [course()]
        memory.keychain["NEWPREFIX.shared"] = WidgetSnapshotStore.encode(courses)
        XCTAssertEqual(WidgetSnapshotStore.loadSnapshot(transport: memory.transport())?.formatVersion, 1)
        XCTAssertTrue(WidgetSnapshotStore.store(courses, transport: memory.transport()))
        let upgraded = try XCTUnwrap(WidgetSnapshotStore.loadSnapshot(transport: memory.transport()))
        XCTAssertEqual(upgraded.formatVersion, 2)
        XCTAssertNotEqual(upgraded.revision.uuidString, "00000000-0000-0000-0000-000000000000")
    }

    func testUnchangedRepublishKeepsRevisionSoAcknowledgementRemainsValid() throws {
        let memory = MemoryStorage()
        let courses = [course()]
        let transport = memory.transport()
        XCTAssertTrue(WidgetSnapshotStore.store(courses, transport: transport))
        let first = try XCTUnwrap(memory.publication)
        _ = WidgetSnapshotStore.loadResult(acknowledge: true, transport: transport)
        XCTAssertTrue(WidgetSnapshotStore.store(courses, transport: transport))
        let second = try XCTUnwrap(memory.publication)
        XCTAssertEqual(first.revision, second.revision)
        XCTAssertTrue(WidgetSnapshotStore.acknowledged(second, transport: transport))
    }

    func testChangedCoursesRequireNewWidgetRead() throws {
        let memory = MemoryStorage()
        let transport = memory.transport()
        XCTAssertTrue(WidgetSnapshotStore.store([course()], transport: transport))
        _ = WidgetSnapshotStore.loadResult(acknowledge: true, transport: transport)
        XCTAssertTrue(WidgetSnapshotStore.store([], transport: transport))
        XCTAssertFalse(WidgetSnapshotStore.acknowledged(try XCTUnwrap(memory.publication), transport: transport))
    }

    func testForcedResyncOfIdenticalCoursesRequiresFreshTimelineReceipt() throws {
        let memory = MemoryStorage()
        let transport = memory.transport()
        let courses = [course()]
        XCTAssertTrue(WidgetSnapshotStore.store(courses, transport: transport))
        _ = WidgetSnapshotStore.loadResult(acknowledge: true, transport: transport)
        let first = try XCTUnwrap(memory.publication)
        XCTAssertTrue(WidgetSnapshotStore.store(courses, transport: transport, forceNewRevision: true))
        let next = try XCTUnwrap(memory.publication)
        XCTAssertNotEqual(first.revision, next.revision)
        XCTAssertFalse(WidgetSnapshotStore.acknowledged(next, transport: transport))
        _ = WidgetSnapshotStore.loadResult(acknowledge: true, transport: transport)
        XCTAssertTrue(WidgetSnapshotStore.acknowledged(next, transport: transport))
    }

    func testPreviewReadingNewDataDoesNotAcknowledgeTimelineUpdate() throws {
        let memory = MemoryStorage()
        let transport = memory.transport()
        let courses = [course()]
        XCTAssertTrue(WidgetSnapshotStore.store(courses, transport: transport))
        XCTAssertEqual(WidgetSnapshotStore.loadResult(acknowledge: false, transport: transport).snapshot?.courses, courses)
        XCTAssertFalse(WidgetSnapshotStore.acknowledged(try XCTUnwrap(memory.publication), transport: transport))
    }

    func testEditingCourseWithSameIdentifierPublishesNewVisibleContent() throws {
        let memory = MemoryStorage()
        let transport = memory.transport()
        var value = course()
        XCTAssertTrue(WidgetSnapshotStore.store([value], transport: transport))
        _ = WidgetSnapshotStore.loadResult(acknowledge: true, transport: transport)
        value.name = "已更新课程"
        value.startTime = "10:00"
        XCTAssertTrue(WidgetSnapshotStore.store([value], transport: transport, forceNewRevision: true))
        let loaded = WidgetSnapshotStore.loadResult(transport: transport)
        XCTAssertEqual(loaded.snapshot?.courses.first?.name, "已更新课程")
        XCTAssertEqual(loaded.snapshot?.courses.first?.startTime, "10:00")
        XCTAssertFalse(WidgetSnapshotStore.acknowledged(try XCTUnwrap(memory.publication), transport: transport))
    }

    func testBundledFallbackNeverSendsExtensionReadReceipt() {
        let memory = MemoryStorage()
        memory.bundled = WidgetSnapshotStore.encode([course()])
        let result = WidgetSnapshotStore.loadResult(acknowledge: true, transport: memory.transport())
        XCTAssertEqual(result.source, .bundle)
        XCTAssertTrue(result.hasScheduleData)
        XCTAssertTrue(memory.receipts.isEmpty)
    }
}
