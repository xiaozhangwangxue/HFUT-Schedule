import XCTest
@testable import HFUTSchedule

final class MaintenanceBackupTests: XCTestCase {
    func testReleaseSelectionOnlyIncludesStableIOSAndUsesNumericOrder() throws {
        let releases = try AppReleaseClient.decode(Data("""
        [{"tag_name":"ios-v1.9.0","name":"older","html_url":"https://example.test/old","draft":false,"prerelease":false},
         {"tag_name":"ios-v1.10.0","html_url":"https://example.test/new","draft":false,"prerelease":false},
         {"tag_name":"ios-v9.0.0","html_url":"https://example.test/beta","draft":false,"prerelease":true},
         {"tag_name":"Android-100","html_url":"https://example.test/android","draft":false,"prerelease":false}]
        """.utf8))
        XCTAssertEqual(releases.map(\.version), ["1.10.0", "1.9.0"])
        XCTAssertEqual(AppReleaseClient.compare("1.2.0", "1.2"), .orderedSame)
        XCTAssertThrowsError(try AppReleaseClient.decode(Data("[]".utf8)))
    }
    func testBackupRejectsUnknownApplicationFileAndInvalidFavorite() throws {
        var appData = BackupApplicationData()
        appData.files["../../cookie-jar"] = Data()
        XCTAssertThrowsError(try appData.validate())
        appData.files = [:]
        appData.favorites = [.init(name: "bad", url: "file:///private/test")]
        XCTAssertThrowsError(try appData.validate())
    }
    @MainActor func testExtendedPreferencesRoundTripIncludesEffectiveAppearanceControls() throws {
        let name = "BackupTests.\(UUID())", defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("zhijian", forKey: AppSettingsKey.defaultCourseSource)
        defaults.set(110.0, forKey: AppSettingsKey.calendarHourHeight)
        defaults.set(1, forKey: AppSettingsKey.teacherDisplayMode)
        defaults.set(false, forKey: AppSettingsKey.focusShowsCard)
        let values = BackupPreferences.capture(from: defaults)
        defaults.removePersistentDomain(forName: name)
        BackupPreferences.restore(values, to: defaults)
        XCTAssertEqual(defaults.string(forKey: AppSettingsKey.defaultCourseSource), "zhijian")
        XCTAssertEqual(defaults.double(forKey: AppSettingsKey.calendarHourHeight), 110)
        XCTAssertEqual(defaults.integer(forKey: AppSettingsKey.teacherDisplayMode), 1)
        XCTAssertFalse(defaults.bool(forKey: AppSettingsKey.focusShowsCard))
    }
    func testXuanchengQuotaDefaultsAndBackupBoundsMatchUpstream() {
        let name = "QuotaDefaultsTests.\(UUID())", defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(BackupPreferences.capture(from: defaults)[AppSettingsKey.xuanchengQuota], .number(200))
        XCTAssertEqual(BackupPreferences.normalized([AppSettingsKey.xuanchengQuota: .number(200)])[AppSettingsKey.xuanchengQuota], .number(200))
        XCTAssertEqual(BackupPreferences.normalized([AppSettingsKey.xuanchengQuota: .number(600)])[AppSettingsKey.xuanchengQuota], .number(500))
        XCTAssertEqual(BackupPreferences.normalized([AppSettingsKey.xuanchengQuota: .number(5)])[AppSettingsKey.xuanchengQuota], .number(10))
        defaults.set(45, forKey: AppSettingsKey.xuanchengQuota)
        XCTAssertEqual(BackupPreferences.capture(from: defaults)[AppSettingsKey.xuanchengQuota], .number(45))
    }
    func testAndroidZIPMigratesRoomAndDataStoreFixtures() throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "android-backup", withExtension: "zip", subdirectory: "Fixtures") ?? Bundle(for: Self.self).url(forResource: "android-backup", withExtension: "zip"))
        let data = try Data(contentsOf: fixture)
        let payload = try ScheduleBackupPayload.decode(data)
        XCTAssertEqual(payload.events?.first?.title, "离线测试日程")
        XCTAssertEqual(payload.applicationData?.favorites.first?.url, "https://example.test/hfut")
        XCTAssertEqual(payload.preferences?[AppSettingsKey.pureBlack], .bool(true))
        XCTAssertEqual(payload.preferences?[AppSettingsKey.teacherDisplayMode], .number(1))
        XCTAssertEqual(payload.preferences?[AppSettingsKey.xuanchengQuota], .number(45))
        var damaged = data; damaged[60] ^= 0xff
        XCTAssertThrowsError(try PortableZIPReader.entries(damaged))
    }
}
