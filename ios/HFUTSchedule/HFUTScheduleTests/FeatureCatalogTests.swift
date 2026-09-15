import XCTest
@testable import HFUTSchedule

final class FeatureCatalogTests: XCTestCase {
    func testFeatureIDsAreUnique() {
        let ids = FeatureCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testCatalogMatchesAndroidSurface() {
        XCTAssertEqual(FeatureCatalog.all.count, 48)
        XCTAssertTrue(FeatureCategory.allCases.allSatisfy { category in
            FeatureCatalog.all.contains { $0.category == category }
        })
    }

    func testEveryFeatureHasAUsableDestination() {
        let unavailable = FeatureCatalog.all.filter {
            $0.url == nil && $0.nativeDestination == nil
        }
        XCTAssertEqual(unavailable.map(\.title), ["AI 助手"])
    }

    func testCourseWeekdayNames() {
        XCTAssertEqual(Course.preview.first?.weekdayName, "周二")
    }
}
