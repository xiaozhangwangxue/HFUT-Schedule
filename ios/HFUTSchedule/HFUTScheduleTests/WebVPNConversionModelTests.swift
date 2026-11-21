import XCTest
import SwiftUI
import UIKit
@testable import HFUTSchedule

@MainActor
final class WebVPNConversionModelTests: XCTestCase {
    func testForwardConversionIsOfflineButOpeningRequiresSession() {
        let model = WebVPNConversionModel()
        model.input = "http://210.45.242.57/"
        XCTAssertTrue(model.canConvert)
        XCTAssertTrue(model.convert())
        XCTAssertEqual(model.result?.host, "webvpn.hfut.edu.cn")
        XCTAssertFalse(model.canOpenResult(hasSession: false))
        XCTAssertTrue(model.canOpenResult(hasSession: true))
    }

    func testRestoredPublicLinkCanOpenWithoutWebVPNSession() {
        let model = WebVPNConversionModel()
        model.direction = .toOriginal
        model.input = AcademicPortal.webVPNAcademicRoot.absoluteString
        XCTAssertTrue(model.convert())
        XCTAssertEqual(model.result?.absoluteString, "http://jxglstu.hfut.edu.cn/eams5-student/")
        XCTAssertTrue(model.canOpenResult(hasSession: false))
    }

    func testSwitchingDirectionPreservesEachFormsOwnInputAndResult() {
        let model = WebVPNConversionModel()
        model.input = "https://lib.hfut.edu.cn/"
        XCTAssertTrue(model.convert())
        let forwardResult = model.result
        model.direction = .toOriginal
        XCTAssertEqual(model.input, "")
        XCTAssertNil(model.result)
        model.input = AcademicPortal.webVPNAcademicRoot.absoluteString
        XCTAssertTrue(model.convert())
        model.direction = .toWebVPN
        XCTAssertEqual(model.input, "https://lib.hfut.edu.cn/")
        XCTAssertEqual(model.result, forwardResult)
    }

    func testEditingInputInvalidatesOldResultBeforeItCanBeCopiedOrOpened() {
        let model = WebVPNConversionModel()
        model.input = "https://lib.hfut.edu.cn/"
        XCTAssertTrue(model.convert())
        model.input = "not a URL"
        XCTAssertNil(model.result)
        XCTAssertFalse(model.canConvert)
        XCTAssertFalse(model.canOpenResult(hasSession: true))
    }

    func testClearResultPreservesInputAndClearInputRemovesResult() {
        let model = WebVPNConversionModel()
        model.input = "https://lib.hfut.edu.cn/"
        XCTAssertTrue(model.convert())
        model.clearResult()
        XCTAssertNil(model.result)
        XCTAssertEqual(model.input, "https://lib.hfut.edu.cn/")
        XCTAssertTrue(model.convert())
        model.input = ""
        XCTAssertNil(model.result)
    }

    func testInvalidAndNonWebSchemesDoNotCreateResults() {
        let model = WebVPNConversionModel()
        for value in ["lib.hfut.edu.cn", "javascript:alert(1)", "file:///tmp/example", "https://"] {
            model.input = value
            XCTAssertFalse(model.convert(), value)
            XCTAssertNil(model.result)
        }
        model.direction = .toOriginal
        model.input = "https://webvpn.hfut.edu.cn/login?cas_login=true"
        XCTAssertFalse(model.convert())
    }

    func testWhitespaceAroundPastedLinkIsIgnored() {
        let model = WebVPNConversionModel()
        model.input = "  https://lib.hfut.edu.cn/ \n"
        XCTAssertTrue(model.convert())
        XCTAssertEqual(model.result, WebVPNURLConverter.convert(URL(string: "https://lib.hfut.edu.cn/")!))
    }

    func testBothConversionPagesRenderWithRealConvertedResults() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for direction in WebVPNConversionModel.Direction.allCases {
            let model = WebVPNConversionModel()
            model.direction = direction
            model.input = direction == .toWebVPN ? "https://lib.hfut.edu.cn/" : AcademicPortal.webVPNAcademicRoot.absoluteString
            XCTAssertTrue(model.convert())
            let host = UIHostingController(rootView: NavigationStack { NativeWebVPNView(model: model) }.preferredColorScheme(.light))
            let window = UIWindow(windowScene: scene)
            window.rootViewController = host
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(400))
            host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let path = FileManager.default.temporaryDirectory.appendingPathComponent("HFUT-webvpn-\(direction.rawValue).png")
            try XCTUnwrap(image.pngData()).write(to: path)
            print("HFUT_WEBVPN_SCREENSHOT=\(path.path)")
            let attachment = XCTAttachment(image: image)
            attachment.name = "WebVPN \(direction.rawValue)"
            attachment.lifetime = .keepAlways
            add(attachment)
            window.isHidden = true
        }
    }
}
