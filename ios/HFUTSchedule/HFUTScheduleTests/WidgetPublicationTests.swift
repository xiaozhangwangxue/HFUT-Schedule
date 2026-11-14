import XCTest
@testable import HFUTSchedule

final class WidgetPublicationTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hfut-widget-publication-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func course(_ title: String = "小组件测试课程") -> Course {
        Course(name: title, teacher: "", location: "测试地点", weekday: 1,
               startTime: "08:00", endTime: "09:40", colorIndex: 0,
               weekIndices: [1, 2], dates: ["2026-11-16", "2026-11-23"], source: "academic")
    }

    @MainActor
    private final class PublicationRecorder {
        struct Attempt {
            let courses: [WidgetCourseSnapshot]
            let termStart: Date?
        }
        var attempts: [Attempt] = []
        var reloadCount = 0
        var allowsWrite = true
        var termStart: Date? = Date(timeIntervalSince1970: 1_800_000_000)

        func store(at url: URL, enabled: Bool = true) -> ScheduleStore {
            ScheduleStore(fileURL: url, syncWidgets: enabled, snapshotPublisher: { [self] courses, termStart in
                attempts.append(Attempt(courses: courses, termStart: termStart))
                return allowsWrite
            }, timelineReloader: { [self] in
                reloadCount += 1
            }, termStartResolver: { [self] _ in termStart })
        }
    }

    @MainActor
    func testExistingValidCoursesRepublishAtStartupWithoutAnyEditOrNetworkSync() throws {
        let url = try temporaryDirectory().appendingPathComponent("courses.json")
        let saved = [course()]
        try JSONEncoder().encode(saved).write(to: url)
        let recorder = PublicationRecorder()
        let store = recorder.store(at: url)
        XCTAssertEqual(store.courses, saved)
        XCTAssertEqual(recorder.attempts.count, 1)
        XCTAssertEqual(recorder.attempts.first?.courses.map(\.id), saved.map(\.id))
        XCTAssertEqual(recorder.attempts.first?.courses.first?.name, saved.first?.name)
        XCTAssertEqual(recorder.attempts.first?.termStart, recorder.termStart)
        XCTAssertEqual(recorder.reloadCount, 1)
        XCTAssertNotNil(store.widgetSyncMessage)
    }

    @MainActor
    func testMissingLocalFileNeverPublishesAnEmptySnapshotOnStartupOrRefresh() throws {
        let url = try temporaryDirectory().appendingPathComponent("missing.json")
        let recorder = PublicationRecorder()
        let store = recorder.store(at: url)
        XCTAssertFalse(store.refreshWidgetSnapshot())
        XCTAssertTrue(recorder.attempts.isEmpty)
        XCTAssertEqual(recorder.reloadCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    @MainActor
    func testCorruptLocalFileNeverOverwritesSharedDataOnStartupOrRefresh() throws {
        let url = try temporaryDirectory().appendingPathComponent("courses.json")
        let damaged = Data("unreadable fixture".utf8)
        try damaged.write(to: url)
        let recorder = PublicationRecorder()
        let store = recorder.store(at: url)
        XCTAssertTrue(store.requiresRecovery)
        XCTAssertFalse(store.refreshWidgetSnapshot())
        XCTAssertTrue(recorder.attempts.isEmpty)
        XCTAssertEqual(recorder.reloadCount, 0)
        XCTAssertEqual(try Data(contentsOf: url), damaged)
    }

    @MainActor
    func testExplicitRefreshRepublishesExistingCoursesForForegroundAndSettingsActions() throws {
        let url = try temporaryDirectory().appendingPathComponent("courses.json")
        let saved = [course()]
        try JSONEncoder().encode(saved).write(to: url)
        let recorder = PublicationRecorder()
        let store = recorder.store(at: url)
        recorder.termStart = Date(timeIntervalSince1970: 1_801_000_000)
        XCTAssertTrue(store.refreshWidgetSnapshot())
        XCTAssertEqual(recorder.attempts.count, 2)
        XCTAssertEqual(recorder.attempts.last?.courses, recorder.attempts.first?.courses)
        XCTAssertEqual(recorder.attempts.last?.termStart, recorder.termStart)
        XCTAssertEqual(recorder.reloadCount, 2)
        XCTAssertEqual(try JSONDecoder().decode([Course].self, from: Data(contentsOf: url)), saved)
    }

    @MainActor
    func testFailedSharedWriteCanRetryWithoutPretendingWidgetWasReloaded() throws {
        let url = try temporaryDirectory().appendingPathComponent("courses.json")
        try JSONEncoder().encode([course()]).write(to: url)
        let recorder = PublicationRecorder()
        recorder.allowsWrite = false
        let store = recorder.store(at: url)
        XCTAssertEqual(recorder.attempts.count, 1)
        XCTAssertEqual(recorder.reloadCount, 0)
        XCTAssertTrue(store.widgetSyncMessage?.contains("未能写入") == true)
        recorder.allowsWrite = true
        XCTAssertTrue(store.refreshWidgetSnapshot())
        XCTAssertEqual(recorder.attempts.count, 2)
        XCTAssertEqual(recorder.reloadCount, 1)
        XCTAssertTrue(store.widgetSyncMessage?.contains("请求刷新") == true)
    }

    @MainActor
    func testExplicitDeletionPublishesEmptySnapshotSoOldCoursesCanBeCleared() throws {
        let url = try temporaryDirectory().appendingPathComponent("courses.json")
        try JSONEncoder().encode([course()]).write(to: url)
        let recorder = PublicationRecorder()
        let store = recorder.store(at: url)
        XCTAssertTrue(store.removeAll())
        XCTAssertEqual(recorder.attempts.count, 2)
        XCTAssertTrue(try XCTUnwrap(recorder.attempts.last).courses.isEmpty)
        XCTAssertEqual(recorder.reloadCount, 2)
        XCTAssertTrue(try JSONDecoder().decode([Course].self, from: Data(contentsOf: url)).isEmpty)
    }

    @MainActor
    func testFirstSuccessfulSavePublishesEvenWhenNoFileExistedAtStartup() throws {
        let url = try temporaryDirectory().appendingPathComponent("courses.json")
        let recorder = PublicationRecorder()
        let store = recorder.store(at: url)
        XCTAssertTrue(recorder.attempts.isEmpty)
        let added = course()
        XCTAssertTrue(store.add(added))
        XCTAssertEqual(recorder.attempts.count, 1)
        XCTAssertEqual(recorder.attempts.first?.courses.map(\.id), [added.id])
        XCTAssertEqual(recorder.reloadCount, 1)
        XCTAssertTrue(store.refreshWidgetSnapshot())
        XCTAssertEqual(recorder.attempts.count, 2)
    }

    @MainActor
    func testValidEmptyFileCanBeExplicitlyRefreshedButDoesNotAutomaticallyEraseSharedData() throws {
        let url = try temporaryDirectory().appendingPathComponent("courses.json")
        try JSONEncoder().encode([Course]()).write(to: url)
        let recorder = PublicationRecorder()
        let store = recorder.store(at: url)
        XCTAssertTrue(recorder.attempts.isEmpty)
        XCTAssertTrue(store.refreshWidgetSnapshot())
        XCTAssertEqual(recorder.attempts.count, 1)
        XCTAssertTrue(try XCTUnwrap(recorder.attempts.first).courses.isEmpty)
        XCTAssertEqual(recorder.reloadCount, 1)
    }

    @MainActor
    func testFailedCourseWriteDoesNotPublishUnsavedCourseChanges() throws {
        let url = try temporaryDirectory().appendingPathComponent("courses.json")
        let saved = [course()]
        try JSONEncoder().encode(saved).write(to: url)
        let recorder = PublicationRecorder()
        let store = recorder.store(at: url)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        XCTAssertFalse(store.add(course("未保存课程")))
        XCTAssertEqual(store.courses, saved)
        XCTAssertEqual(recorder.attempts.count, 1)
        XCTAssertEqual(recorder.reloadCount, 1)
    }

    @MainActor
    func testDisabledWidgetSyncNeverCallsPublisherOrReloader() throws {
        let url = try temporaryDirectory().appendingPathComponent("courses.json")
        try JSONEncoder().encode([course()]).write(to: url)
        let recorder = PublicationRecorder()
        let store = recorder.store(at: url, enabled: false)
        XCTAssertFalse(store.refreshWidgetSnapshot())
        XCTAssertTrue(store.add(course("新增测试课程")))
        XCTAssertTrue(store.removeAll())
        XCTAssertTrue(recorder.attempts.isEmpty)
        XCTAssertEqual(recorder.reloadCount, 0)
    }
}
