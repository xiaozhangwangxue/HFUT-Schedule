import Foundation
import XCTest
@testable import HFUTSchedule

private final class ScannerFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []
    private var token: String? = "Bearer offline-scanner-fixture"
    let responses: [(Int, String)]
    init(_ responses: [(Int, String)]) { self.responses = responses }
    func readToken() -> String? { lock.lock(); defer { lock.unlock() }; return token }
    func writeToken(_ value: String) { lock.lock(); token = value.isEmpty ? nil : value; lock.unlock() }
    func take(_ request: URLRequest) -> (Int, String) {
        lock.lock(); defer { lock.unlock() }
        let index = requests.count; requests.append(request)
        return responses.indices.contains(index) ? responses[index] : (500, "{}")
    }
    var recorded: [URLRequest] { lock.lock(); defer { lock.unlock() }; return requests }
}

private final class ScannerFixtureProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var fixtures: [String: ScannerFixture] = [:]
    static func register(_ fixture: ScannerFixture, id: String) { lock.lock(); fixtures[id] = fixture; lock.unlock() }
    static func remove(_ id: String) { lock.lock(); fixtures.removeValue(forKey: id); lock.unlock() }
    override class func canInit(with request: URLRequest) -> Bool { request.value(forHTTPHeaderField: "X-Scanner-Fixture") != nil }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let fixture = request.value(forHTTPHeaderField: "X-Scanner-Fixture").flatMap { Self.fixtures[$0] }
        Self.lock.unlock()
        guard let fixture else { client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return }
        let (status, body) = fixture.take(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class ZhiJianScannerTests: XCTestCase {
    private func session(_ fixture: ScannerFixture) -> (URLSession, String) {
        let identifier = UUID().uuidString
        ScannerFixtureProtocol.register(fixture, id: identifier)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScannerFixtureProtocol.self]
        config.httpAdditionalHeaders = ["X-Scanner-Fixture": identifier]
        return (URLSession(configuration: config), identifier)
    }
    func testCASUsesFixedOfficialHostAndOnlyConfirmsAfterScanSuccess() async throws {
        let fixture = ScannerFixture([(200, #"{"msg":"success"}"#), (200, #"{"msg":"success","data":"ok"}"#)])
        let (session, identifier) = session(fixture)
        defer { session.invalidateAndCancel(); ScannerFixtureProtocol.remove(identifier) }
        let client = ZhiJianScannerClient(session: session, readToken: { fixture.readToken() }, writeToken: { fixture.writeToken($0) })
        try await client.confirm("https://untrusted.example/cas/app/scanQrCodeLogin?uuid=offline-code")
        let requests = fixture.recorded
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests.allSatisfy { $0.url?.host == "wx.hfut.edu.cn" && $0.url?.scheme == "https" })
        XCTAssertEqual(requests.map { $0.url?.path }, ["/cas/app/scanQrCodeLogin", "/cas/app/confirmLogin"])
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer offline-scanner-fixture" })
        XCTAssertEqual(URLComponents(url: requests[1].url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "offline-code")
    }
    func testFailedScanNeverConfirmsAndCannotTreatUnsuccessfulAsSuccess() async {
        let fixture = ScannerFixture([(200, #"{"msg":"unsuccessful"}"#)])
        let (session, identifier) = session(fixture)
        defer { session.invalidateAndCancel(); ScannerFixtureProtocol.remove(identifier) }
        let client = ZhiJianScannerClient(session: session, readToken: { fixture.readToken() }, writeToken: { fixture.writeToken($0) })
        do { try await client.confirm("https://cas.hfut.edu.cn/cas/app/scanQrCodeLogin?uuid=offline-code"); XCTFail("Failed scan was accepted") }
        catch { XCTAssertEqual((error as? ZhiJianScannerError)?.localizedDescription, ZhiJianScannerError.scanFailed.localizedDescription) }
        XCTAssertEqual(fixture.recorded.count, 1)
    }
    func testExpiredTokenIsDeletedAndReturnsLoginRequired() async {
        let fixture = ScannerFixture([(401, #"{"msg":"expired"}"#)])
        let (session, identifier) = session(fixture)
        defer { session.invalidateAndCancel(); ScannerFixtureProtocol.remove(identifier) }
        let client = ZhiJianScannerClient(session: session, readToken: { fixture.readToken() }, writeToken: { fixture.writeToken($0) })
        do { try await client.confirm("https://cas.hfut.edu.cn/cas/app/scanQrCodeLogin?uuid=offline-code"); XCTFail("Expired token was accepted") }
        catch { XCTAssertEqual((error as? ZhiJianScannerError)?.localizedDescription, ZhiJianScannerError.loginRequired.localizedDescription) }
        XCTAssertNil(fixture.readToken())
        XCTAssertEqual(fixture.recorded.count, 1)
    }
    func testSharedAuthorizedDataRejectsUnlistedPathsWithoutRequest() async {
        let fixture = ScannerFixture([])
        let (session, identifier) = session(fixture)
        defer { session.invalidateAndCancel(); ScannerFixtureProtocol.remove(identifier) }
        let client = ZhiJianScannerClient(session: session, readToken: { fixture.readToken() }, writeToken: { fixture.writeToken($0) })
        do { _ = try await client.authorizedData(path: "/other"); XCTFail("Unexpected path accepted") }
        catch {}
        XCTAssertTrue(fixture.recorded.isEmpty)
    }
}
