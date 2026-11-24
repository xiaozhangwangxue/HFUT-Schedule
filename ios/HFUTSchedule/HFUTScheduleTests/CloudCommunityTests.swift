import XCTest
@testable import HFUTSchedule

@MainActor
final class CloudCommunityTests: XCTestCase {
    private var testSession: URLSession!
    private var credentialAccount: String!
    private var defaults: UserDefaults!
    override func setUp() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CloudCommunityFixtureProtocol.self]
        testSession = URLSession(configuration: config)
        credentialAccount = "cloud-community-test-\(UUID())"
        defaults = UserDefaults(suiteName: credentialAccount)!
    }
    override func tearDown() async throws {
        testSession.invalidateAndCancel()
        AppSecretStore.write("", account: credentialAccount)
        defaults.removePersistentDomain(forName: credentialAccount)
        CloudCommunityFixtureProtocol.handler = nil
    }
    private func client() -> CloudCommunityClient {
        CloudCommunityClient(session: testSession, baseURL: URL(string: "https://fixture.invalid/")!, anonymousKey: "fixture-public-key", credentialAccount: credentialAccount, defaults: defaults)
    }
    func testSchoolEmailAndUTCConversionAndScopeMatching() throws {
        XCTAssertEqual(try CloudCommunityClient.schoolEmail(" 2026000000 "), "2026000000@mail.hfut.edu.cn")
        XCTAssertThrowsError(try CloudCommunityClient.schoolEmail("user@example.com"))
        let event = try JSONDecoder().decode(CloudCommunityEvent.self, from: Self.eventData)
        XCTAssertTrue(event.isValid)
        XCTAssertTrue(event.applies(to: "测试班级", campus: "HEFEI"))
        XCTAssertFalse(event.applies(to: "其它班级", campus: "HEFEI"))
        XCTAssertFalse(event.applies(to: "测试班级", campus: "XUANCHENG"))
        XCTAssertEqual(CloudCommunityDate.string(try XCTUnwrap(event.start)), "2030-01-01T00:00:00")
    }
    func testPublicListAnd401RefreshUseRealEndpointAndPayloadContract() async throws {
        var checks = 0, refreshes = 0
        CloudCommunityFixtureProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "fixture-public-key")
            switch request.url!.path {
            case "/auth/v1/token":
                let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
                if query?.first?.value == "refresh_token" {
                    refreshes += 1
                    let body = try JSONSerialization.jsonObject(with: Self.requestBody(request)) as! [String: Any]
                    XCTAssertEqual(body["refresh_token"] as? String, "fixture-refresh")
                    return (200, Self.authData(token: "fixture-new"))
                }
                let body = try JSONSerialization.jsonObject(with: Self.requestBody(request)) as! [String: Any]
                XCTAssertEqual(body["email"] as? String, "2026000000@mail.hfut.edu.cn")
                return (200, Self.authData(token: "fixture-old"))
            case "/functions/v1/check-login":
                checks += 1
                if checks == 1 { return (401, Data("{}".utf8)) }
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-new")
                return (200, Data("{}".utf8))
            case "/rest/v1/event":
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
                XCTAssertTrue(query?.contains(where: { $0.name == "end_time" && $0.value?.hasPrefix("gt.") == true }) == true)
                return (200, Data("[".utf8) + Self.eventData + Data("]".utf8))
            default: XCTFail("Unexpected fixture endpoint"); return (500, Data())
            }
        }
        let client = client()
        try await client.signIn(account: "2026000000", password: "offline-fixture-password")
        try await client.verifySession()
        XCTAssertEqual(checks, 2); XCTAssertEqual(refreshes, 1)
        try await client.loadEvents()
        XCTAssertEqual(client.events.map(\.id), [42])
        XCTAssertTrue(client.hasSession)
        client.signOut(); XCTAssertFalse(client.hasSession)
    }
    func testImportOverwritesExistingLocalRecordWithoutDuplicating() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = CustomEventStore(fileURL: folder.appendingPathComponent("events.json"))
        let client = client()
        var event = try JSONDecoder().decode(CloudCommunityEvent.self, from: Self.eventData)
        let initialWasUpdate = try await client.importEvent(event, into: store)
        XCTAssertFalse(initialWasUpdate)
        let firstID = try XCTUnwrap(store.events.first?.id)
        event.name = "已更新的离线测试日程"
        let nextWasUpdate = try await client.importEvent(event, into: store)
        XCTAssertTrue(nextWasUpdate)
        XCTAssertEqual(store.events.count, 1)
        XCTAssertEqual(store.events.first?.id, firstID)
        XCTAssertEqual(store.events.first?.title, event.name)
        XCTAssertEqual(store.events.first?.groupID, "supabase:42")
    }
    func testContributionManagementAndDownloadCountPayloadsMatchUpstream() async throws {
        var mutations: [String] = []
        CloudCommunityFixtureProtocol.handler = { request in
            let path = request.url!.path
            if path == "/auth/v1/token" { return (200, Self.authData(token: "fixture-owner")) }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-owner")
            if path == "/functions/v1/check-login" { return (200, Data("{}".utf8)) }
            if path == "/rest/v1/rpc/get_event_fork_count" {
                let body = try JSONSerialization.jsonObject(with: Self.requestBody(request)) as! [String: Any]
                XCTAssertEqual((body["target_event_id"] as? NSNumber)?.intValue, 42)
                return (200, Data("7".utf8))
            }
            guard path == "/rest/v1/event" else { XCTFail("Unexpected endpoint"); return (500, Data()) }
            let method = request.httpMethod ?? "GET"
            if method == "GET" { return (200, Data("[".utf8) + Self.eventData + Data("]".utf8)) }
            mutations.append(method)
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
            if method == "PATCH" || method == "DELETE" { XCTAssertEqual(query?.first(where: { $0.name == "id" })?.value, "eq.42") }
            if method == "POST" || method == "PATCH" {
                let body = try JSONSerialization.jsonObject(with: Self.requestBody(request)) as! [String: Any]
                XCTAssertEqual(body["contributor_email"] as? String, "2026000000@mail.hfut.edu.cn")
                XCTAssertEqual(body["contributor_class"] as? String, "测试班级(肥)")
                XCTAssertEqual(body["type"] as? String, "SCHEDULE")
                XCTAssertEqual(body["start_time"] as? String, "2030-01-01T00:00:00")
                XCTAssertNil(body["id"])
            }
            return (200, Data("[]".utf8))
        }
        let client = client()
        try await client.signIn(account: "2026000000", password: "offline-fixture-password")
        let event = try JSONDecoder().decode(CloudCommunityEvent.self, from: Self.eventData)
        try await client.contribute(event, className: "测试班级(肥)", update: false)
        try await client.contribute(event, className: "测试班级(肥)", update: true)
        await client.loadForkCount(42)
        XCTAssertEqual(client.forkCounts[42], 7)
        try await client.delete(event)
        XCTAssertEqual(mutations, ["POST", "PATCH", "DELETE"])
        XCTAssertTrue(client.myEvents.isEmpty)
    }
    nonisolated private static var eventData: Data { Data("""
    {"id":42,"name":"离线测试日程","description":"仅用于离线测试","time_description":"测试地点",
    "start_time":"2030-01-01T00:00:00","end_time":"2030-01-01T01:00:00","contributor_email":"2026000000@mail.hfut.edu.cn",
    "contributor_class":"测试班级","applicable_classes":"测试班级","created_time":"2029-12-01T00:00:00+00:00",
    "url":"https://example.test/event","campus":"HEFEI","type":"SCHEDULE"}
    """.utf8) }
    nonisolated private static func authData(token: String) -> Data { Data("""
    {"access_token":"\(token)","refresh_token":"fixture-refresh","user":{"email":"2026000000@mail.hfut.edu.cn"}}
    """.utf8) }
    nonisolated private static func requestBody(_ request: URLRequest) -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; data.append(contentsOf: buffer.prefix(count)) }
        return data
    }
}

private final class CloudCommunityFixtureProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.badServerResponse) }
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
