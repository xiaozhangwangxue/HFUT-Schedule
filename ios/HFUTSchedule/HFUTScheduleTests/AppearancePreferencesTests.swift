import XCTest
import UIKit
@testable import HFUTSchedule

final class AppearancePreferencesTests: XCTestCase {
    func testTeacherMigrationPreservesExplicitNewChoice() {
        let name = "AppearanceTests.\(UUID())", defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: AppSettingsKey.showTeacherInSquare)
        AppSettingsKey.migrateLegacyPreferences(in: defaults)
        XCTAssertEqual(defaults.integer(forKey: AppSettingsKey.teacherDisplayMode), 2)
        defaults.set(1, forKey: AppSettingsKey.teacherDisplayMode)
        AppSettingsKey.migrateLegacyPreferences(in: defaults)
        XCTAssertEqual(defaults.integer(forKey: AppSettingsKey.teacherDisplayMode), 1)
    }

    func testImageExtractionChoosesDominantColorRatherThanAverage() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32), format: format).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 8, height: 32))
        }
        XCTAssertEqual(try ThemeImageColorExtractor.dominantHex(in: XCTUnwrap(image.pngData())), "FF0000")
        XCTAssertThrowsError(try ThemeImageColorExtractor.dominantHex(in: Data("not an image".utf8)))
    }
}
