import XCTest
import WebKit
@testable import HFUTSchedule

@MainActor
final class PortalBrowserToolsTests: XCTestCase {
    func testCurrentOriginCookieParserPreservesEqualsAndSecureFlag() throws {
        let https = try PortalBrowserController.cookies(header: "session=abc==; theme=dark", for: URL(string: "https://lib.hfut.edu.cn/a")!)
        XCTAssertEqual(https.map(\.name), ["session", "theme"])
        XCTAssertEqual(https.first?.value, "abc==")
        XCTAssertTrue(https.allSatisfy { $0.domain == "lib.hfut.edu.cn" && $0.path == "/" && $0.isSecure })
        let http = try PortalBrowserController.cookies(header: "a=b", for: URL(string: "http://210.45.242.57/")!)
        XCTAssertFalse(try XCTUnwrap(http.first).isSecure)
    }

    func testCookieParserRejectsMalformedHeadersAndNonWebOrigins() {
        for header in ["", ";;", "broken", "name\n=x", "name=x\r\nOther: x", "bad name=x"] {
            XCTAssertThrowsError(try PortalBrowserController.cookies(header: header, for: URL(string: "https://lib.hfut.edu.cn/")!))
        }
        XCTAssertThrowsError(try PortalBrowserController.cookies(header: "a=b", for: URL(string: "file:///tmp/page.html")!))
    }

    func testCurrentPageBookmarkUsesExistingNavigationDataFormatAndDeduplicates() throws {
        let name = "HFUTBrowserTools-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let url = URL(string: "https://lib.hfut.edu.cn/?a=b#page")!
        try WebFavoriteStore.save(title: "图书馆", url: url, defaults: defaults)
        try WebFavoriteStore.save(title: "新标题", url: url, defaults: defaults)
        let saved = WebFavoriteStore.records(defaults: defaults)
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.name, "新标题")
        XCTAssertTrue(WebFavoriteStore.contains(url, defaults: defaults))
        let data = try XCTUnwrap(defaults.data(forKey: "webNavigationFavoritesV1"))
        let legacyCompatible = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: String]])
        XCTAssertEqual(legacyCompatible.first?["url"], url.absoluteString)
        XCTAssertNotNil(legacyCompatible.first?["id"])
        try WebFavoriteStore.remove(url, defaults: defaults)
        XCTAssertTrue(WebFavoriteStore.records(defaults: defaults).isEmpty)
    }

    func testFindRunsOnTheDisplayedWebViewUsingOfflineHTML() async throws {
        let loaded = expectation(description: "offline page loaded")
        let delegate = OfflinePageDelegate { loaded.fulfill() }
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        webView.navigationDelegate = delegate
        let controller = PortalBrowserController()
        controller.webView = webView
        webView.loadHTMLString("<html><body><p>HFUT library</p><p>HFUT courses</p></body></html>", baseURL: nil)
        await fulfillment(of: [loaded], timeout: 5)
        controller.synchronize()
        controller.find("HFUT")
        try await waitForMessage(controller)
        XCTAssertEqual(controller.findMessage, "已定位匹配文字")
        controller.find("not-in-this-local-page")
        for _ in 0..<100 where controller.findMessage != "未找到匹配文字" { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(controller.findMessage, "未找到匹配文字")
        controller.clearFind()
        for _ in 0..<100 where controller.findMessage != nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNil(controller.findMessage)
        _ = delegate
    }

    private func waitForMessage(_ controller: PortalBrowserController) async throws {
        for _ in 0..<200 where controller.findMessage == nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNotNil(controller.findMessage)
    }

    private final class OfflinePageDelegate: NSObject, WKNavigationDelegate {
        let didLoad: () -> Void
        init(didLoad: @escaping () -> Void) { self.didLoad = didLoad }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) { didLoad() }
    }
}
