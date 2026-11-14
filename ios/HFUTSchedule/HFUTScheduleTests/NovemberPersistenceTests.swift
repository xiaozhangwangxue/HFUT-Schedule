import XCTest
@testable import HFUTSchedule

final class NovemberPersistenceTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hfut-persistence-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func course(_ title: String = "测试课程") -> Course {
        Course(name: title, teacher: "", location: "测试地点", weekday: 1,
               startTime: "08:00", endTime: "09:00", colorIndex: 0)
    }

    private func event(_ title: String = "测试日程") -> CustomEvent {
        CustomEvent(title: title, start: Date(timeIntervalSince1970: 1_800_000_000),
                    end: Date(timeIntervalSince1970: 1_800_003_600))
    }

    @MainActor
    func testUnreadableScheduleCannotBeOverwrittenByAutomaticSyncOrEdits() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("courses.json")
        let damaged = Data("not a course backup".utf8)
        try damaged.write(to: url)
        let store = ScheduleStore(fileURL: url, syncWidgets: false)
        XCTAssertTrue(store.requiresRecovery)
        XCTAssertNotNil(store.storageError)
        XCTAssertFalse(store.add(course()))
        XCTAssertFalse(store.removeAll())
        XCTAssertFalse(store.replaceAcademicCourses(with: [course()]))
        XCTAssertEqual(try Data(contentsOf: url), damaged)
        XCTAssertTrue(store.courses.isEmpty)

        let restored = [course("恢复课程")]
        XCTAssertTrue(store.replace(with: restored))
        XCTAssertFalse(store.requiresRecovery)
        XCTAssertNil(store.storageError)
        XCTAssertEqual(store.courses, restored)
        XCTAssertEqual(try JSONDecoder().decode([Course].self, from: Data(contentsOf: url)), restored)
        let copies = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("courses.recovery-") }
        XCTAssertEqual(copies.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(copies.first)), damaged)
    }

    @MainActor
    func testScheduleWriteFailureIsRetryableWithoutPublishingUnsavedData() throws {
        let directory = try temporaryDirectory()
        let blocker = directory.appendingPathComponent("blocked")
        try Data("temporary obstruction".utf8).write(to: blocker)
        let url = blocker.appendingPathComponent("courses.json")
        let store = ScheduleStore(fileURL: url, syncWidgets: false)
        let added = course()
        XCTAssertFalse(store.add(added))
        XCTAssertFalse(store.requiresRecovery)
        XCTAssertNotNil(store.storageError)
        XCTAssertTrue(store.courses.isEmpty)

        try FileManager.default.removeItem(at: blocker)
        XCTAssertTrue(store.add(added))
        XCTAssertEqual(store.courses, [added])
        XCTAssertNil(store.storageError)
        let reloaded = ScheduleStore(fileURL: url, syncWidgets: false)
        XCTAssertEqual(reloaded.courses, [added])
    }

    @MainActor
    func testScheduleFailedDeleteKeepsPreviouslySavedPublishedCourses() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("courses.json")
        let saved = [course()]
        try JSONEncoder().encode(saved).write(to: url)
        let store = ScheduleStore(fileURL: url, syncWidgets: false)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        XCTAssertFalse(store.remove(id: saved[0].id))
        XCTAssertEqual(store.courses, saved)
        XCTAssertFalse(store.requiresRecovery)

        try FileManager.default.removeItem(at: url)
        XCTAssertTrue(store.remove(id: saved[0].id))
        XCTAssertTrue(store.courses.isEmpty)
        XCTAssertNil(store.storageError)
    }

    @MainActor
    func testInjectedSchedulePathDoesNotApplyGlobalPreviewMigration() throws {
        let url = try temporaryDirectory().appendingPathComponent("courses.json")
        try JSONEncoder().encode(Course.preview).write(to: url)
        let store = ScheduleStore(fileURL: url, syncWidgets: false)
        XCTAssertEqual(store.courses, Course.preview)
        XCTAssertEqual(try JSONDecoder().decode([Course].self, from: Data(contentsOf: url)), Course.preview)
    }

    @MainActor
    func testUnreadableEventsRequireExplicitRestoreAndPreserveOriginalBytes() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("custom-events.json")
        let damaged = Data("not an event backup".utf8)
        try damaged.write(to: url)
        let store = CustomEventStore(fileURL: url)
        XCTAssertTrue(store.requiresRecovery)
        XCTAssertFalse(store.save(event()))
        XCTAssertFalse(store.remove(UUID()))
        XCTAssertEqual(try Data(contentsOf: url), damaged)

        let restored = [event("恢复日程")]
        XCTAssertTrue(store.restore(restored))
        XCTAssertEqual(store.events, restored)
        XCTAssertFalse(store.requiresRecovery)
        XCTAssertNil(store.storageError)
        let copies = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("custom-events.recovery-") }
        XCTAssertEqual(copies.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(copies.first)), damaged)
    }

    @MainActor
    func testEventWriteFailureCanRetrySaveAndDelete() throws {
        let directory = try temporaryDirectory()
        let blocker = directory.appendingPathComponent("blocked")
        try Data("temporary obstruction".utf8).write(to: blocker)
        let url = blocker.appendingPathComponent("custom-events.json")
        let store = CustomEventStore(fileURL: url)
        let added = event()
        XCTAssertFalse(store.save(added))
        XCTAssertTrue(store.events.isEmpty)
        XCTAssertNotNil(store.storageError)
        XCTAssertFalse(store.requiresRecovery)
        try FileManager.default.removeItem(at: blocker)
        XCTAssertTrue(store.save(added))
        XCTAssertNil(store.storageError)
        XCTAssertEqual(store.events, [added])

        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        XCTAssertFalse(store.remove(added.id))
        XCTAssertEqual(store.events, [added])
        XCTAssertFalse(store.requiresRecovery)
        try FileManager.default.removeItem(at: url)
        XCTAssertTrue(store.remove(added.id))
        XCTAssertTrue(store.events.isEmpty)
        XCTAssertNil(store.storageError)
    }

    @MainActor
    func testEventRestoreRejectsInvalidOrDuplicateEntriesWithoutChangingSavedEvents() throws {
        let url = try temporaryDirectory().appendingPathComponent("custom-events.json")
        let store = CustomEventStore(fileURL: url)
        let original = event()
        XCTAssertTrue(store.save(original))
        let savedBytes = try Data(contentsOf: url)
        XCTAssertFalse(store.restore([original, original]))
        XCTAssertEqual(store.events, [original])
        XCTAssertEqual(try Data(contentsOf: url), savedBytes)
        XCTAssertFalse(store.requiresRecovery)
        var invalid = original
        invalid.title = "  "
        XCTAssertFalse(store.restore([invalid]))
        XCTAssertEqual(try Data(contentsOf: url), savedBytes)
        XCTAssertTrue(store.save(event("后续可重试")))
        XCTAssertNil(store.storageError)
    }

    @MainActor
    func testSemanticallyInvalidEventFileIsPreservedAsUnreadable() throws {
        let url = try temporaryDirectory().appendingPathComponent("custom-events.json")
        var invalid = event()
        invalid.end = invalid.start.addingTimeInterval(-1)
        let data = try JSONEncoder().encode([invalid])
        try data.write(to: url)
        let store = CustomEventStore(fileURL: url)
        XCTAssertTrue(store.requiresRecovery)
        XCTAssertTrue(store.events.isEmpty)
        XCTAssertFalse(store.save(event()))
        XCTAssertEqual(try Data(contentsOf: url), data)
    }
}
