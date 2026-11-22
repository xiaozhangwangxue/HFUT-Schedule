import XCTest
import UIKit
@testable import HFUTSchedule

final class CASCaptchaRecognizerTests: XCTestCase {
    func testUpstreamModelRecognizesDeterministicallySampledTrainingFixtures() async throws {
        let folder = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "CaptchaFixtures", withExtension: nil))
        let labels = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix(".gt.txt") }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertEqual(labels.count, 14)
        for label in labels {
            let expected = try String(contentsOf: label, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            let image = folder.appendingPathComponent(label.lastPathComponent.replacingOccurrences(of: ".gt.txt", with: ".png"))
            let actual = try await CASCaptchaRecognizer.shared.recognize(Data(contentsOf: image))
            XCTAssertEqual(actual, expected, label.lastPathComponent)
        }
    }

    func testMalformedImageFailsInsteadOfFillingGuessedText() async {
        do {
            _ = try await CASCaptchaRecognizer.shared.recognize(Data("<html>Login required</html>".utf8))
            XCTFail("Not an image")
        } catch {
            XCTAssertEqual(error as? CASCaptchaRecognizer.RecognitionError, .invalidImage)
        }
    }

    func testMissingModelFailsWithoutCrashing() async throws {
        let folder = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "CaptchaFixtures", withExtension: nil))
        let image = try Data(contentsOf: folder.appendingPathComponent("222a.png"))
        do {
            _ = try await CASCaptchaRecognizer(modelDirectory: nil).recognize(image)
            XCTFail("Missing model")
        } catch {
            XCTAssertEqual(error as? CASCaptchaRecognizer.RecognitionError, .missingModel)
        }
    }

    func testGrayscaleMatchesUpstreamWeightedRGBAndDimensions() throws {
        let bytes: [UInt8] = [255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255]
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        let cgImage = try XCTUnwrap(CGImage(width: 3, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: 12, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let data = try XCTUnwrap(UIImage(cgImage: cgImage).pngData())
        let gray = try CASCaptchaRecognizer.grayscaleImage(data)
        XCTAssertEqual(gray.width, 3)
        XCTAssertEqual(gray.height, 1)
        XCTAssertEqual(Array(gray.pixels), [76, 149, 29])
    }
}
