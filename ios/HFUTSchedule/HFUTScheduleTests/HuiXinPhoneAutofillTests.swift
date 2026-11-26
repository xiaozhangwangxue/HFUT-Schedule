import XCTest
import WebKit
@testable import HFUTSchedule

@MainActor final class HuiXinPhoneAutofillTests: XCTestCase {
    private let phone = "13800138000"
    private let officialURL = URL(string: "http://121.251.19.62/charge-app/?name=pays&id=222#/pays?id=222")!
    private let fields = """
    <div class="weui-cell"><label class="weui-label">手机号码</label><input class="weui-input" id="phone" placeholder="请输入"></div>
    <label>充值金额<input id="amount" type="number"></label>
    <label>手机验证码<input id="otp" type="tel"></label>
    <input id="password" type="password"><input id="hiddenPhone" name="phone" style="display:none">
    <button onclick="window.submitted=true">充值</button>
    """

    func testOnlyKnownPhoneFeeOriginsAndNormalizedPhonesAreAccepted() throws {
        let value = try XCTUnwrap(HuiXinPhoneAutofill(phone: "+86 138 0013 8000", itemID: 222, url: officialURL))
        XCTAssertEqual(value.phone, phone)
        for url in ["https://example.com/charge-app/?id=222", "http://121.251.19.62.example.com/charge-app/?id=222",
                    "http://121.251.19.62/plat/?id=222", "http://121.251.19.62:8080/charge-app/?id=222",
                    "http://121.251.19.62/charge-app/?id=26", "http://121.251.19.62/charge-app/?id=222&id=222"] {
            XCTAssertNil(HuiXinPhoneAutofill(phone: phone, itemID: 222, url: URL(string: url)!))
        }
        XCTAssertNil(HuiXinPhoneAutofill(phone: "123", itemID: 222, url: officialURL))
        XCTAssertNil(HuiXinPhoneAutofill(phone: phone, itemID: 1, url: URL(string: "http://121.251.19.62/charge-app/?id=1")!))
    }

    func testOfficialVueStyleFieldUpdatesTheBoundModelWithoutSubmitting() async throws {
        let page = try await load(fields, policy: policy())
        try await waitForValue("phone", phone, in: page.web)
        let model = try await page.web.evaluateJavaScript("window.model || ''") as? String
        XCTAssertEqual(model, phone)
        for id in ["amount", "otp", "password", "hiddenPhone"] {
            let value = try await page.web.evaluateJavaScript("document.getElementById('\(id)').value") as? String
            XCTAssertEqual(value, "", id)
        }
        let submitted = try await page.web.evaluateJavaScript("!!window.submitted") as? Bool
        XCTAssertEqual(submitted, false)
    }

    func testFormAppearingAfterPageLoadIsFilled() async throws {
        let page = try await load("<div id='app-box'></div>", policy: policy())
        let json = String(data: try JSONEncoder().encode(fields), encoding: .utf8)!
        _ = try await page.web.evaluateJavaScript("document.getElementById('app-box').innerHTML = \(json)")
        try await waitForValue("phone", phone, in: page.web)
    }

    func testLatePhoneInstallsOnceAndRetainsOtherBrowserScripts() async throws {
        let page = try await load(fields, policy: nil)
        page.web.configuration.userContentController.addUserScript(WKUserScript(source: "window.otherBrowserTool = true", injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        page.controller.update(policy(), on: page.web)
        try await waitForValue("phone", phone, in: page.web)
        page.controller.update(policy(), on: page.web)
        XCTAssertEqual(page.web.configuration.userContentController.userScripts.count, 2)
        XCTAssertTrue(page.web.configuration.userContentController.userScripts.allSatisfy(\.isForMainFrameOnly))
    }

    func testExistingValueAndUserClearingAutofillArePreserved() async throws {
        let existing = fields.replacingOccurrences(of: "id=\"phone\"", with: "id=\"phone\" value=\"13900139000\"")
        let saved = try await load(existing, policy: policy())
        try await waitForValue("phone", "13900139000", in: saved.web)
        let page = try await load(fields, policy: policy())
        try await waitForValue("phone", phone, in: page.web)
        _ = try await page.web.evaluateJavaScript("const p=document.getElementById('phone');p.value='';p.dispatchEvent(new Event('input',{bubbles:true}));document.body.appendChild(document.createElement('div')); true")
        try await Task.sleep(for: .milliseconds(80))
        try await waitForValue("phone", "", in: page.web)
    }

    func testForeignHostDifferentFeeAndPaymentRouteNeverReceivePhone() async throws {
        for url in [URL(string: "https://example.com/charge-app/?id=222")!,
                    URL(string: "http://121.251.19.62/charge-app/?id=26")!,
                    URL(string: "http://121.251.19.62/charge-app/?id=222#/confirmPay")!,
                    URL(string: "http://121.251.19.62/charge-app/?id=222#/pays?id=26")!] {
            let page = try await load(fields, policy: policy(), url: url)
            try await waitForValue("phone", "", in: page.web)
        }
    }

    func testSinglePhoneBasedAccountLabelSupportsLaundryForm() async throws {
        let url = URL(string: "http://121.251.19.62/charge-app/?id=26#/pays?id=26")!
        let form = "<div class='weui-cell'><label class='weui-label'>洗衣账号</label><input id='account' placeholder='请输入'></div><label>充值金额<input id='amount' type='number'></label>"
        let page = try await load(form, policy: HuiXinPhoneAutofill(phone: phone, itemID: 26, url: url), url: url)
        try await waitForValue("account", phone, in: page.web)
        let amount = try await page.web.evaluateJavaScript("document.getElementById('amount').value") as? String
        XCTAssertEqual(amount, "")
    }

    private func policy() -> HuiXinPhoneAutofill? { HuiXinPhoneAutofill(phone: phone, itemID: 222, url: officialURL) }
    private func waitForValue(_ id: String, _ expected: String, in web: WKWebView) async throws {
        var last: String?
        for _ in 0..<100 {
            last = try await web.evaluateJavaScript("document.getElementById('\(id)').value") as? String
            if last == expected { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(last, expected)
    }
    private func load(_ body: String, policy: HuiXinPhoneAutofill?, url: URL? = nil) async throws -> Page {
        let loaded = expectation(description: "offline official-form fixture loaded")
        let page = Page { loaded.fulfill() }
        page.controller.update(policy, on: page.web)
        page.web.loadHTMLString("""
        <html><meta name="viewport" content="width=device-width"><body>\(body)
        <script>document.addEventListener('input',e=>{if(e.target.id==='phone')window.model=e.target.value;});</script>
        </body></html>
        """, baseURL: url ?? officialURL)
        await fulfillment(of: [loaded], timeout: 5)
        return page
    }
    private final class Page: NSObject, WKNavigationDelegate {
        let web: WKWebView
        let controller = HuiXinPhoneAutofillController()
        let loaded: () -> Void
        init(loaded: @escaping () -> Void) {
            let configuration = WKWebViewConfiguration(); configuration.websiteDataStore = .nonPersistent()
            web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 800), configuration: configuration)
            self.loaded = loaded
            super.init(); web.navigationDelegate = self
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) { loaded() }
    }
}
