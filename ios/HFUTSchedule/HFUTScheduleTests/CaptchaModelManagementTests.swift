import XCTest
@testable import HFUTSchedule

final class CaptchaModelManagementTests: XCTestCase {
    func testValidatedImportRejectsInvalidReplacementAndSupportsDeletion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("model-store-test-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bundled = try XCTUnwrap(Bundle.main.url(forResource: "tessdata", withExtension: nil))
            .appendingPathComponent("captcha.traineddata")
        let model = try Data(contentsOf: bundled)
        try CaptchaModelStore.install(model, directory: directory)
        let installed = directory.appendingPathComponent("captcha.traineddata")
        XCTAssertEqual(try installed.resourceValues(forKeys: [.fileSizeKey]).fileSize, model.count)
        XCTAssertThrowsError(try CaptchaModelStore.install(Data(), directory: directory))
        XCTAssertThrowsError(try CaptchaModelStore.install(Data("invalid model fixture".utf8), directory: directory))
        XCTAssertEqual(try installed.resourceValues(forKeys: [.fileSizeKey]).fileSize, model.count)
        try CaptchaModelStore.removeCustom(directory: directory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: installed.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundled.path))
    }
}
