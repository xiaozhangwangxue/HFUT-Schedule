import XCTest
import SwiftUI
import UIKit
@testable import HFUTSchedule

@MainActor
final class CASCaptchaAutofillModelTests: XCTestCase {
    func testRecognizesDisplayedBytesAndPreservesFiveCharacterResult() async throws {
        let recognizer = ControlledRecognizer()
        let model = CASCaptchaAutofillModel(recognizer: recognizer)
        model.activate(enabled: true)
        let displayedImage = Data([1, 2, 3])
        model.setImage(displayedImage)
        try await waitForRequests(1, on: recognizer)
        let recognizedImage = await recognizer.image(at: 0)
        XCTAssertEqual(recognizedImage, displayedImage)
        await recognizer.complete(0, result: .success("  wgc4g\n"))
        try await waitForState(.filled, on: model)
        XCTAssertEqual(model.text, "wgc4g", "The client must not force a four-character format")
    }

    func testDisabledAutofillDoesNotInvokeRecognizerAndAllowsManualInput() async {
        let recognizer = ControlledRecognizer()
        let model = CASCaptchaAutofillModel(recognizer: recognizer)
        model.activate(enabled: false)
        model.setImage(Data([1]))
        model.userEdited("manual5")
        await Task.yield()
        let requestCount = await recognizer.requestCount
        XCTAssertEqual(requestCount, 0)
        XCTAssertEqual(model.text, "manual5")
        XCTAssertFalse(model.canRetry)
    }

    func testManualInputWinsOverDelayedRecognition() async throws {
        let recognizer = ControlledRecognizer()
        let model = CASCaptchaAutofillModel(recognizer: recognizer)
        model.activate(enabled: true)
        model.setImage(Data([1]))
        try await waitForRequests(1, on: recognizer)
        model.userEdited("typed")
        await recognizer.complete(0, result: .success("old-auto"))
        await settleTasks()
        XCTAssertEqual(model.text, "typed")
        XCTAssertEqual(model.state, .manual)
        XCTAssertFalse(model.canRetry)
    }

    func testManualClearAlsoInvalidatesPendingRecognition() async throws {
        let recognizer = ControlledRecognizer()
        let model = CASCaptchaAutofillModel(recognizer: recognizer)
        model.activate(enabled: true)
        model.setImage(Data([1]))
        try await waitForRequests(1, on: recognizer)
        model.userEdited("")
        await recognizer.complete(0, result: .success("old-auto"))
        await settleTasks()
        XCTAssertEqual(model.text, "")
        XCTAssertEqual(model.state, .manual)
        XCTAssertTrue(model.canRetry)
    }

    func testNewImageRejectsOldResultEvenWhenOldRequestCompletesLast() async throws {
        let recognizer = ControlledRecognizer()
        let model = CASCaptchaAutofillModel(recognizer: recognizer)
        model.activate(enabled: true)
        model.setImage(Data([1]))
        try await waitForRequests(1, on: recognizer)
        model.setImage(Data([2]))
        try await waitForRequests(2, on: recognizer)
        await recognizer.complete(1, result: .success("new-image"))
        try await waitForState(.filled, on: model)
        await recognizer.complete(0, result: .success("old-image"))
        await settleTasks()
        XCTAssertEqual(model.text, "new-image")
    }

    func testSameImageBytesStillCreateANewGeneration() async throws {
        let recognizer = ControlledRecognizer()
        let model = CASCaptchaAutofillModel(recognizer: recognizer)
        model.activate(enabled: true)
        model.setImage(Data([1]))
        try await waitForRequests(1, on: recognizer)
        model.setImage(Data([1]))
        try await waitForRequests(2, on: recognizer)
        await recognizer.complete(0, result: .success("stale"))
        await settleTasks()
        XCTAssertEqual(model.text, "")
        XCTAssertTrue(model.isRecognizing)
        await recognizer.complete(1, result: .success("current"))
        try await waitForState(.filled, on: model)
        XCTAssertEqual(model.text, "current")
    }

    func testDisablingCancelsPendingResultAndReenablingUsesCurrentImage() async throws {
        let recognizer = ControlledRecognizer()
        let model = CASCaptchaAutofillModel(recognizer: recognizer)
        model.activate(enabled: true)
        model.setImage(Data([9]))
        try await waitForRequests(1, on: recognizer)
        model.setEnabled(false)
        await recognizer.complete(0, result: .success("late"))
        await settleTasks()
        XCTAssertEqual(model.state, .disabled)
        XCTAssertEqual(model.text, "")
        model.setEnabled(true)
        try await waitForRequests(2, on: recognizer)
        let retriedImage = await recognizer.image(at: 1)
        XCTAssertEqual(retriedImage, Data([9]))
        await recognizer.complete(1, result: .success("fresh"))
        try await waitForState(.filled, on: model)
        XCTAssertEqual(model.text, "fresh")
    }

    func testLeavingPageRejectsDelayedResultAndDoesNotStartNewWorkWhileInactive() async throws {
        let recognizer = ControlledRecognizer()
        let model = CASCaptchaAutofillModel(recognizer: recognizer)
        model.activate(enabled: true)
        model.setImage(Data([1]))
        try await waitForRequests(1, on: recognizer)
        model.deactivate()
        model.setEnabled(true)
        await recognizer.complete(0, result: .success("late"))
        await settleTasks()
        XCTAssertEqual(model.text, "")
        XCTAssertFalse(model.isRecognizing)
        let requestCount = await recognizer.requestCount
        XCTAssertEqual(requestCount, 1)
    }

    func testLoginInvalidationPreventsLateAutofill() async throws {
        let recognizer = ControlledRecognizer()
        let model = CASCaptchaAutofillModel(recognizer: recognizer)
        model.activate(enabled: true)
        model.setImage(Data([1]))
        try await waitForRequests(1, on: recognizer)
        model.cancelPendingRecognition()
        await recognizer.complete(0, result: .success("late"))
        await settleTasks()
        XCTAssertEqual(model.text, "")
        XCTAssertFalse(model.isRecognizing)
    }

    func testRecognitionFailureKeepsManualFallbackAndRetryAvailable() async throws {
        let recognizer = ControlledRecognizer()
        let model = CASCaptchaAutofillModel(recognizer: recognizer)
        model.activate(enabled: true)
        model.setImage(Data([1]))
        try await waitForRequests(1, on: recognizer)
        await recognizer.complete(0, result: .failure(FixtureError.failed))
        try await waitForState(.failed, on: model)
        XCTAssertEqual(model.text, "")
        XCTAssertTrue(model.canRetry)
        XCTAssertNotNil(model.statusText)
        model.retry()
        try await waitForRequests(2, on: recognizer)
        await recognizer.complete(1, result: .success("retry-ok"))
        try await waitForState(.filled, on: model)
        XCTAssertEqual(model.text, "retry-ok")
    }

    func testEmptyRecognitionDoesNotFillGuessedCharacters() async throws {
        let recognizer = ControlledRecognizer()
        let model = CASCaptchaAutofillModel(recognizer: recognizer)
        model.activate(enabled: true)
        model.setImage(Data([1]))
        try await waitForRequests(1, on: recognizer)
        await recognizer.complete(0, result: .success(" \n"))
        try await waitForState(.failed, on: model)
        XCTAssertEqual(model.text, "")
        model.userEdited("手动")
        XCTAssertEqual(model.text, "手动")
    }

    func testClearingImageDropsRecognitionAndNewImageClearsOldManualInput() async throws {
        let recognizer = ControlledRecognizer()
        let model = CASCaptchaAutofillModel(recognizer: recognizer)
        model.activate(enabled: true)
        model.setImage(Data([1]))
        try await waitForRequests(1, on: recognizer)
        model.setImage(nil)
        await recognizer.complete(0, result: .success("old-image"))
        await settleTasks()
        XCTAssertEqual(model.text, "")
        XCTAssertFalse(model.canRetry)
        model.userEdited("old-manual")
        model.setImage(Data([2]))
        try await waitForRequests(2, on: recognizer)
        XCTAssertEqual(model.text, "")
        await recognizer.complete(1, result: .success("new-image"))
        try await waitForState(.filled, on: model)
        XCTAssertEqual(model.text, "new-image")
    }

    func testNativeCASDirectAndWebVPNPagesRenderWithLocalCaptchaAutofill() async throws {
        let defaults = UserDefaults.standard
        let oldUsername = defaults.object(forKey: "academicUsername")
        let oldEnabled = defaults.object(forKey: "enableOcrCaptcha")
        defaults.set("", forKey: "academicUsername")
        defaults.set(true, forKey: "enableOcrCaptcha")
        defer {
            if let oldUsername { defaults.set(oldUsername, forKey: "academicUsername") }
            else { defaults.removeObject(forKey: "academicUsername") }
            if let oldEnabled { defaults.set(oldEnabled, forKey: "enableOcrCaptcha") }
            else { defaults.removeObject(forKey: "enableOcrCaptcha") }
        }
        let folder = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "CaptchaFixtures", withExtension: nil))
        let imageData = try Data(contentsOf: folder.appendingPathComponent("222a.png"))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let oldKeyWindow = scene.windows.first(where: \.isKeyWindow)
        defer { oldKeyWindow?.makeKeyAndVisible() }
        for mode in AcademicConnectionMode.allCases {
            let view = NativeCASLoginView(
                mode: mode,
                onAuthenticated: { _, _, _ in XCTFail("Autofill must never submit login") },
                onPreparationFailure: { _ in XCTFail("The injected local preparation must not fetch CAS") },
                recognizer: CASCaptchaRecognizer.shared,
                initialPreparation: CASLoginPreparation(execution: "offline-fixture", needsCaptcha: true, captchaImageData: imageData)
            )
            let host = UIHostingController(rootView: NavigationStack { view }.preferredColorScheme(.light))
            let window = UIWindow(windowScene: scene)
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            var didFill = false
            for _ in 0..<60 {
                try await Task.sleep(for: .milliseconds(50))
                host.view.layoutIfNeeded()
                if textFields(in: host.view).contains(where: { $0.text == "222a" }) { didFill = true; break }
            }
            XCTAssertTrue(didFill, "The real SwiftUI captcha field should receive the local OCR result")
            XCTAssertFalse(textFields(in: host.view).contains { !($0.text ?? "").isEmpty && $0.text != "222a" },
                           "The screenshot must not contain a stored account name")
            let screenshot = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let output = FileManager.default.temporaryDirectory.appendingPathComponent("HFUT-native-cas-\(mode.rawValue)-autofill.png")
            try XCTUnwrap(screenshot.pngData()).write(to: output)
            print("HFUT_CAPTCHA_SCREENSHOT=\(output.path)")
            let attachment = XCTAttachment(image: screenshot)
            attachment.name = "Native CAS \(mode.rawValue) local autofill"
            attachment.lifetime = .keepAlways
            add(attachment)
            window.isHidden = true
        }
    }

    private func textFields(in view: UIView) -> [UITextField] {
        (view as? UITextField).map { [$0] } ?? view.subviews.flatMap { textFields(in: $0) }
    }

    private func waitForRequests(_ count: Int, on recognizer: ControlledRecognizer) async throws {
        for _ in 0..<500 {
            if await recognizer.requestCount >= count { return }
            await Task.yield()
        }
        XCTFail("Recognition did not start")
        throw FixtureError.timeout
    }

    private func waitForState(_ state: CASCaptchaAutofillModel.State, on model: CASCaptchaAutofillModel) async throws {
        for _ in 0..<500 {
            if model.state == state { return }
            await Task.yield()
        }
        XCTFail("Autofill state did not settle")
        throw FixtureError.timeout
    }

    private func settleTasks() async {
        for _ in 0..<12 { await Task.yield() }
    }

    private enum FixtureError: Error { case failed, timeout }

    /// Deliberately ignores Task cancellation until the test releases it, proving the model's
    /// generation/manual-edit guards also reject engines that finish a synchronous OCR call late.
    private actor ControlledRecognizer: CASCaptchaRecognizing {
        private var requests: [(Data, CheckedContinuation<String, Error>?)] = []
        var requestCount: Int { requests.count }

        func recognize(_ imageData: Data) async throws -> String {
            try await withCheckedThrowingContinuation { continuation in
                requests.append((imageData, continuation))
            }
        }

        func image(at index: Int) -> Data { requests[index].0 }

        func complete(_ index: Int, result: Result<String, Error>) {
            guard let continuation = requests[index].1 else { return }
            requests[index].1 = nil
            continuation.resume(with: result)
        }
    }
}
