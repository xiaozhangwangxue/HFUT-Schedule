import Foundation
import XCTest
@testable import HFUTSchedule

private actor CASPreparationFixture {
    struct Reply {
        var status = 200
        var body = ""
        var headers: [String: String] = [:]
    }
    let replies: [Reply]
    private(set) var requests: [URLRequest] = []
    init(_ replies: [Reply]) { self.replies = replies }
    func respond(_ request: URLRequest) throws -> (Data, URLResponse) {
        let index = requests.count
        requests.append(request)
        guard replies.indices.contains(index), let url = request.url else { throw URLError(.badServerResponse) }
        let reply = replies[index]
        return (Data(reply.body.utf8), HTTPURLResponse(url: url, statusCode: reply.status,
            httpVersion: "HTTP/2", headerFields: reply.headers)!)
    }
}

final class CASLoginPreparationTests: XCTestCase {
    private let key = "0123456789abcdef"
    private let key2 = "fedcba9876543210"
    private let cookieURL = URL(string: "https://cas.hfut.edu.cn/cas/checkInitParams")!
    private func login(_ execution: String = "fresh-execution", _ session: String = "fresh-session") -> CASPreparationFixture.Reply {
        .init(body: "<input name='execution' value='\(execution)'>", headers: ["Set-Cookie": "SESSION=\(session); Path=/cas/"])
    }
    private func challenge(_ header: String) -> CASPreparationFixture.Reply {
        .init(body: #"{"vercode":true}"#, headers: ["Set-Cookie": header])
    }
    private func client(_ fixture: CASPreparationFixture, mode: AcademicConnectionMode = .direct,
                        staleKey: String? = nil) -> CASLoginClient {
        let jar = URLSessionConfiguration.ephemeral.httpCookieStorage!
        if let staleKey {
            jar.setCookie(HTTPCookie(properties: [.name:"LOGIN_FLAVORING", .value:staleKey,
                .domain:"cas.hfut.edu.cn", .path:"/cas/"])!)
        }
        return CASLoginClient(mode: mode, transport: { try await fixture.respond($0) }, cookieStorage: jar,
            persistCookies: { _ in }, clearCASCookies: {})
    }

    func testFoldedFieldsHandleBothOrdersNoSpacesAndNewlines() {
        let a = "LOGIN_FLAVORING=\(key)", b = "JSESSIONID=fixture-session"
        for text in [a+", "+b, b+","+a, a+","+b] {
            let response = HTTPURLResponse(url: cookieURL, statusCode: 200, httpVersion: nil,
                headerFields: ["Set-Cookie":text])!
            XCTAssertEqual(CASCookieParser.value(named: "LOGIN_FLAVORING", in: response), key)
            XCTAssertEqual(Set(CASCookieParser.cookies(from: response).map(\.name)), ["LOGIN_FLAVORING","JSESSIONID"])
        }
    }
    func testRawFoldedHeaderLinesAreSplitBeforeFoundationParsing() {
        // HTTPURLResponse's test initializer itself rejects CR/LF fields;
        // exercise the incoming raw-field normalization independently.
        let fields = ["LOGIN_FLAVORING=\(key)\nJSESSIONID=fixture", "JSESSIONID=fixture\r\nLOGIN_FLAVORING=\(key)"]
        for text in fields {
            XCTAssertEqual(CASCookieParser.value(named: "LOGIN_FLAVORING", inCookieText: text), key)
            XCTAssertEqual(Set(CASCookieParser.cookies(headerValues: [text], url: cookieURL).map(\.name)), ["LOGIN_FLAVORING","JSESSIONID"])
        }
    }
    func testExpiresCommaIsNotAnotherCookieAndAttributesArePreserved() throws {
        let response = HTTPURLResponse(url: cookieURL, statusCode: 200, httpVersion: nil, headerFields: [
            "Set-Cookie":"JSESSIONID=fixture; Expires=Wed, 09 Jun 2038 10:18:14 GMT; Path=/cas/; Secure; HttpOnly,LOGIN_FLAVORING=\(key); Path=/cas/"
        ])!
        let cookies = CASCookieParser.cookies(from: response)
        XCTAssertEqual(cookies.count, 2)
        let session = try XCTUnwrap(cookies.first { $0.name == "JSESSIONID" })
        XCTAssertTrue(session.isSecure); XCTAssertEqual(session.path, "/cas/"); XCTAssertNotNil(session.expiresDate)
    }
    func testVirtualCookiesAcceptWhitespaceQuotesAndJSONEnvelope() throws {
        let text = "SESSION=fixture; LOGIN_FLAVORING = \"\(key)\"; JSESSIONID=fixture"
        XCTAssertEqual(CASCookieParser.virtualValue(named: "LOGIN_FLAVORING", data: Data(text.utf8)), key)
        let json = try JSONSerialization.data(withJSONObject: text, options: .fragmentsAllowed)
        XCTAssertEqual(CASCookieParser.virtualValue(named: "LOGIN_FLAVORING", data: json), key)
    }
    func testCookieLookupRejectsDifferentNamesEmptyAndHeaderInjection() {
        for text in ["OTHER_LOGIN_FLAVORING=\(key)", "LOGIN_FLAVORING_OLD=\(key)", "LOGIN_FLAVORING=", "LOGIN_FLAVORING=\"bad;key\"", "LOGIN_FLAVORING=\"bad\r\nkey\""] {
            XCTAssertNil(CASCookieParser.value(named: "LOGIN_FLAVORING", inCookieText: text))
        }
    }
    func testDirectPreparationAndPostUseExactFreshKeyAndSeparateChallengeCookies() async throws {
        let fixture = CASPreparationFixture([login(), challenge("JSESSIONID=fresh-js,LOGIN_FLAVORING=\(key)"),
            .init(body:"synthetic-captcha"), .init(status:401,body:"invalid credentials")])
        let client = client(fixture)
        let value = try await client.prepare()
        XCTAssertEqual(value.execution,"fresh-execution"); XCTAssertTrue(value.needsCaptcha)
        XCTAssertEqual(value.captchaImageData,Data("synthetic-captcha".utf8))
        do { _ = try await client.login(username:"synthetic-user",password:"synthetic-password",captcha:"1234",execution:value.execution); XCTFail("Fixture rejection accepted") }
        catch CASLoginError.invalidCredentials {} catch { XCTFail("Unexpected error \(error)") }
        let requests = await fixture.requests
        XCTAssertEqual(requests.count,4)
        XCTAssertNil(requests[0].value(forHTTPHeaderField:"Cookie"))
        XCTAssertNil(requests[1].value(forHTTPHeaderField:"Cookie"))
        XCTAssertEqual(requests[2].value(forHTTPHeaderField:"Cookie"),"JSESSIONID=fresh-js")
        XCTAssertEqual(requests[3].value(forHTTPHeaderField:"Cookie"),"SESSION=fresh-session;JSESSIONID=fresh-js;LOGIN_FLAVORING=\(key)")
        let body = try XCTUnwrap(String(data:try XCTUnwrap(requests[3].httpBody),encoding:.utf8))
        let fields = URLComponents(string:"https://example.test/?"+body)?.queryItems ?? []
        XCTAssertEqual(fields.first { $0.name == "password" }?.value,try CASLoginClient.encryptAES("synthetic-password",key:key))
        XCTAssertFalse(body.contains("synthetic-password"))
        XCTAssertTrue(requests.prefix(2).allSatisfy { $0.cachePolicy == .reloadIgnoringLocalCacheData })
    }
    func testMissingFreshKeyDoesNotReuseCookieJarAndRetriesOnlyOnce() async throws {
        let fixture = CASPreparationFixture([login(),challenge("JSESSIONID=first"),login("second","second-session"),challenge("JSESSIONID=second")])
        let client = client(fixture,staleKey:key)
        do { _ = try await client.prepare(includeCaptcha:false); XCTFail("Stale key accepted") }
        catch CASLoginError.missingFlavoring {} catch { XCTFail("Unexpected error \(error)") }
        do { _ = try await client.login(username:"fixture",password:"fixture",captcha:"",execution:"old"); XCTFail("Failed preparation permitted a POST") }
        catch CASLoginError.missingFlavoring {} catch { XCTFail("Unexpected error \(error)") }
        let requests = await fixture.requests
        XCTAssertEqual(requests.count,4); XCTAssertTrue(requests.allSatisfy { $0.httpMethod != "POST" })
    }
    func testRetryGetsNewExecutionSessionAndEncryptionKeyAsOnePreparation() async throws {
        let fixture = CASPreparationFixture([login("old","old-session"),challenge("JSESSIONID=old-js"),
            login("new","new-session"),challenge("LOGIN_FLAVORING=\(key2),JSESSIONID=new-js"),.init(status:401)])
        let client = client(fixture)
        let value = try await client.prepare(includeCaptcha:false)
        XCTAssertEqual(value.execution,"new")
        do { _ = try await client.login(username:"fixture",password:"fixture",captcha:"",execution:value.execution) }
        catch CASLoginError.invalidCredentials {} catch { XCTFail("Unexpected error \(error)") }
        let requests = await fixture.requests
        XCTAssertEqual(requests.last?.value(forHTTPHeaderField:"Cookie"),"SESSION=new-session;JSESSIONID=new-js;LOGIN_FLAVORING=\(key2)")
    }
    func testInvalidAESKeyFailsBeforeCaptchaOrPasswordPost() async {
        let fixture = CASPreparationFixture([login(),challenge("LOGIN_FLAVORING=short,JSESSIONID=js"),login(),challenge("LOGIN_FLAVORING=short,JSESSIONID=js")])
        do { _ = try await client(fixture).prepare(); XCTFail("Invalid AES key accepted") }
        catch CASLoginError.invalidEncryptionKey {} catch { XCTFail("Unexpected error \(error)") }
        let requests = await fixture.requests
        XCTAssertEqual(requests.count,4); XCTAssertFalse(requests.contains { $0.url?.path == "/cas/vercode" })
    }
    func testHTTPFailureIsNotRetriedAsMissingKey() async {
        let fixture = CASPreparationFixture([.init(status:503)])
        do { _ = try await client(fixture).prepare(); XCTFail("HTTP failure accepted") }
        catch CASLoginError.http(503) {} catch { XCTFail("Unexpected error \(error)") }
        let requests = await fixture.requests; XCTAssertEqual(requests.count,1)
    }
    func testWebVPNUsesVirtualKeyAndOnlyGatewayTicketInPost() async throws {
        let fixture = CASPreparationFixture([login(),.init(headers:["Set-Cookie":"wengine_vpn_ticketwebvpn_hfut_edu_cn=fixture-vpn; Path=/"]),
            challenge(""),.init(body:"SESSION=virtual;LOGIN_FLAVORING = \"\(key)\";JSESSIONID=virtual-js"),.init(status:401)])
        let client = client(fixture,mode:.webVPN)
        let value = try await client.prepare(includeCaptcha:false)
        do { _ = try await client.login(username:"fixture",password:"fixture",captcha:"",execution:value.execution) }
        catch CASLoginError.invalidCredentials {} catch { XCTFail("Unexpected error \(error)") }
        let requests = await fixture.requests
        XCTAssertEqual(requests.count,5)
        XCTAssertTrue(requests[2].url!.path.hasSuffix("/cas/checkInitParams"))
        XCTAssertEqual(requests[3].url?.path,"/wengine-vpn/cookie")
        XCTAssertEqual(requests[4].value(forHTTPHeaderField:"Cookie"),"wengine_vpn_ticketwebvpn_hfut_edu_cn=fixture-vpn")
    }
    func testWebVPNLoginExportsOnlyAFreshAuthenticatedGrantForOtherCampusServices() async throws {
        let fixture = CASPreparationFixture([login(),.init(headers:["Set-Cookie":"wengine_vpn_ticketwebvpn_hfut_edu_cn=fixture-vpn; Path=/"]),
            challenge(""),.init(body:"LOGIN_FLAVORING=\(key);JSESSIONID=virtual-js"),.init(status:200),
            .init(body:"SESSION=virtual;TGC=synthetic-fresh-grant")])
        let jar = URLSessionConfiguration.ephemeral.httpCookieStorage!
        let client = CASLoginClient(mode:.webVPN,excludesAcademic:true,transport:{ try await fixture.respond($0) },
            cookieStorage:jar,persistCookies:{ _ in },clearCASCookies:{})
        let preparation = try await client.prepare(includeCaptcha:false)
        let cookies = try await client.login(username:"fixture",password:"fixture",captcha:"",execution:preparation.execution)
        let granting = try XCTUnwrap(cookies.first { $0.name == "TGC" })
        XCTAssertEqual(granting.value,"synthetic-fresh-grant")
        XCTAssertEqual(granting.domain,"cas.hfut.edu.cn")
        let requests = await fixture.requests
        XCTAssertEqual(requests.count,6)
        XCTAssertEqual(requests.last?.url?.path,"/wengine-vpn/cookie")
        XCTAssertFalse(requests.last?.value(forHTTPHeaderField:"Cookie")?.contains("TGC=") ?? false)
    }

    func testWebVPNHTTP200WithoutGrantCannotClaimSuccessfulLogin() async throws {
        let fixture = CASPreparationFixture([login(),.init(headers:["Set-Cookie":"wengine_vpn_ticketwebvpn_hfut_edu_cn=fixture-vpn; Path=/"]),
            challenge(""),.init(body:"LOGIN_FLAVORING=\(key);JSESSIONID=virtual-js"),.init(status:200),
            .init(body:"SESSION=anonymous;LOGIN_FLAVORING=\(key)")])
        let client = CASLoginClient(mode:.webVPN,excludesAcademic:true,transport:{ try await fixture.respond($0) },
            cookieStorage:URLSessionConfiguration.ephemeral.httpCookieStorage!,persistCookies:{ _ in },clearCASCookies:{})
        let preparation = try await client.prepare(includeCaptcha:false)
        do { _ = try await client.login(username:"fixture",password:"fixture",captcha:"",execution:preparation.execution); XCTFail("Anonymous gateway accepted") }
        catch CASLoginError.invalidCredentials {} catch { XCTFail("Unexpected error \(error)") }
        let requests = await fixture.requests; XCTAssertEqual(requests.count,6)
    }

}
