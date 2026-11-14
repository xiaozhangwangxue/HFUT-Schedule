import XCTest
@testable import HFUTSchedule

final class NovemberUpgradeTests: XCTestCase {
    func testCloningCreatesIndependentEventAndPreservesContents() {
        let original = CustomEvent(title: "测试日程", detail: "合成说明", location: "测试地点",
            start: Date(timeIntervalSince1970: 100), end: Date(timeIntervalSince1970: 200), groupID: "reserved")
        let copy = original.cloned()
        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertEqual(copy.title, original.title)
        XCTAssertEqual(copy.start, original.start)
        XCTAssertEqual(copy.end, original.end)
        XCTAssertNil(copy.groupID)
    }

    func testEventVisibilityAndDeadlinePriorityMatchUpstream() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let past = CustomEvent(title: "past", start: now.addingTimeInterval(-7200), end: now.addingTimeInterval(-3600))
        XCTAssertFalse(past.appears(on: now, showExpired: false))
        XCTAssertTrue(past.appears(on: now, showExpired: true))
        let near = CustomEvent(title: "near", start: now, end: now.addingTimeInterval(72 * 3600), kind: .deadline)
        let later = CustomEvent(title: "later", start: now, end: now.addingTimeInterval(72 * 3600 + 1), kind: .deadline)
        XCTAssertTrue(near.isImportant(on: now))
        XCTAssertFalse(later.isImportant(on: now))
        XCTAssertTrue(later.appears(on: now, showExpired: false))
    }

    func testMultiDayEventProjectsIntoEachCalendarDayAndClipsAtWeekBoundary() {
        let cal = ScheduleCalendar.calendar
        let monday = ScheduleCalendar.isoDate("2026-11-09")!
        let start = cal.date(byAdding: .hour, value: 23, to: monday)!
        let event = CustomEvent(title: "跨天", start: start, end: start.addingTimeInterval(3 * 3600))
        let blocks = event.timetableCourses(in: monday, calendar: cal)
        XCTAssertEqual(blocks.map(\.weekday), [1, 2])
        XCTAssertEqual(blocks.map(\.startTime), ["23:00", "00:00"])
        XCTAssertEqual(blocks.map(\.endTime), ["24:00", "02:00"])
        XCTAssertTrue(event.timetableCourses(in: cal.date(byAdding: .day, value: 7, to: monday)!, calendar: cal).isEmpty)
    }

    func testDefaultPreferencesAreIncludedInBackup() {
        let suite = "HFUTScheduleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let captured = BackupPreferences.capture(from: defaults)
        XCTAssertEqual(captured[AppSettingsKey.autoTermStart], .bool(true))
        XCTAssertEqual(captured[AppSettingsKey.showFinishedToday], .bool(true))
        XCTAssertEqual(captured[AppSettingsKey.backgroundBlur], .number(0.35))
    }

    func testLegacyBackupKeepsExistingEventsAndSettingsUntouched() throws {
        let backup = try ScheduleBackupPayload.decode(Data("[]".utf8))
        XCTAssertTrue(backup.courses.isEmpty)
        XCTAssertNil(backup.events)
        XCTAssertNil(backup.preferences)
    }

    func testNewBackupRoundTripsEventsAndPreferences() throws {
        let event = CustomEvent(title: "截止测试", start: Date(timeIntervalSince1970: 100),
            end: Date(timeIntervalSince1970: 200), kind: .deadline)
        let payload = ScheduleBackupPayload(courses: [], events: [event], preferences: [AppSettingsKey.focusCardAction: .number(2)])
        let restored = try ScheduleBackupPayload.decode(JSONEncoder().encode(payload))
        XCTAssertEqual(restored.events, [event])
        XCTAssertEqual(restored.preferences?[AppSettingsKey.focusCardAction], .number(2))
    }

    func testUnknownBackupVersionRejectedBeforeRestore() {
        XCTAssertThrowsError(try ScheduleBackupPayload.decode(Data("{\"formatVersion\":999,\"courses\":[]}".utf8)))
    }

    func testPreferenceImportIgnoresForeignFlagsSecretsAndWrongTypes() {
        let result = BackupPreferences.normalized([
            "academic-password": .string("synthetic-not-a-real-secret"),
            "androidPredictiveBack": .bool(true),
            AppSettingsKey.pureBlack: .string("false"),
            AppSettingsKey.appearance: .string("invalid"),
            AppSettingsKey.focusCardAction: .number(99),
            AppSettingsKey.xuanchengQuota: .number(-1),
            AppSettingsKey.showFinishedToday: .bool(false)
        ])
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[AppSettingsKey.focusCardAction], .number(2))
        XCTAssertEqual(result[AppSettingsKey.xuanchengQuota], .number(5))
        XCTAssertEqual(result[AppSettingsKey.showFinishedToday], .bool(false))
    }

    func testManualTermStartRespectsAutomaticSwitch() {
        let suite = "HFUTScheduleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(1_799_020_800.0, forKey: AppSettingsKey.manualTermStart)
        XCTAssertNil(ScheduleCalendar.manualTermStart(defaults: defaults))
        defaults.set(false, forKey: AppSettingsKey.autoTermStart)
        XCTAssertNotNil(ScheduleCalendar.manualTermStart(defaults: defaults))
        defaults.set(true, forKey: AppSettingsKey.autoTermStart)
        XCTAssertNil(ScheduleCalendar.manualTermStart(defaults: defaults))
    }

    func testBirthdayDoesNotDependOnCloudAnnouncements() {
        let date = ScheduleCalendar.isoDate("2026-11-14")!
        XCTAssertTrue(BirthdayGreeting.isBirthday(fields: ["出生日期": "2000-11-14"], on: date))
        XCTAssertFalse(BirthdayGreeting.isBirthday(fields: ["出生日期": "2000-11-15"], on: date))
        XCTAssertFalse(BirthdayGreeting.isBirthday(fields: [:], on: date))
    }

    @MainActor
    func testUnreadableEventFileIsPreservedAndDoesNotCrashOrGetOverwritten() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("events.json")
        let corrupt = Data("invalid-json-fixture".utf8)
        try corrupt.write(to: url)
        let store = CustomEventStore(fileURL: url)
        XCTAssertNotNil(store.storageError)
        store.save(CustomEvent(title: "test", start: Date(), end: Date().addingTimeInterval(60)))
        XCTAssertEqual(try Data(contentsOf: url), corrupt)
        store.restore([])
        XCTAssertNil(store.storageError)
        XCTAssertEqual(try JSONDecoder().decode([CustomEvent].self, from: Data(contentsOf: url)), [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).count, 2)
    }
}
