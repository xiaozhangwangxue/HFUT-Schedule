import XCTest
@testable import HFUTSchedule

final class CampusWeatherTests: XCTestCase {
    private static let nowJSON = #"{"code":"200","fxLink":"https://www.qweather.com/weather/hefei-101220101.html","now":{"temp":"19","feelsLike":"18","humidity":"62","text":"多云","icon":"101","windDir":"东北风","windScale":"2"}}"#
    private static let warningJSON = #"{"code":"200","fxLink":"https://www.qweather.com/severe-weather/hefei-101220101.html","warning":[{"title":"测试气象台发布预警","typeName":"大风","text":"测试预警正文"}]}"#
    private static let freeJSON = #"{"current":{"temperature_2m":21.5,"relative_humidity_2m":63,"apparent_temperature":20.2,"weather_code":3,"wind_speed_10m":8.4}}"#

    func testQWeatherNowDecodesUpstreamStringFieldsAndDetailLink() throws {
        let result = try QWeatherPayloadDecoder.now(from: Data(Self.nowJSON.utf8))
        XCTAssertEqual(result.observation.temperature, 19)
        XCTAssertEqual(result.observation.apparent, 18)
        XCTAssertEqual(result.observation.humidity, 62)
        XCTAssertEqual(result.observation.condition, "多云")
        XCTAssertEqual(result.observation.windDescription, "东北风 · 2级")
        XCTAssertEqual(result.detailURL?.absoluteString, CampusWeatherLocation.hefei.officialWeatherURL.absoluteString)
    }

    func testQWeatherWarningRetainsTitleTypeTextAndEnvelopeLink() throws {
        let result = try QWeatherPayloadDecoder.warnings(from: Data(Self.warningJSON.utf8))
        XCTAssertEqual(result.items.first?.title, "测试气象台发布预警")
        XCTAssertEqual(result.items.first?.typeName, "大风")
        XCTAssertEqual(result.items.first?.text, "测试预警正文")
        XCTAssertEqual(result.detailURL, CampusWeatherLocation.hefei.officialWarningURL)
    }

    func testEmptySuccessfulWarningPayloadIsDistinctFromUnavailability() throws {
        let result = try QWeatherPayloadDecoder.warnings(from: Data(#"{"code":"200","warning":[]}"#.utf8))
        XCTAssertEqual(result.items, [])
        XCTAssertNotEqual(CampusWeatherWarningState.available(result.items), .unavailable("未连接"))
    }

    func testWarningErrorCodeAndUntrustedDetailURLAreRejected() throws {
        XCTAssertThrowsError(try QWeatherPayloadDecoder.warnings(from: Data(#"{"code":"401","warning":[]}"#.utf8)))
        let result = try QWeatherPayloadDecoder.warnings(from: Data(#"{"code":"200","warning":[],"fxLink":"javascript:alert(1)"}"#.utf8))
        XCTAssertNil(result.detailURL)
        let otherHost = try QWeatherPayloadDecoder.warnings(from: Data(#"{"code":"200","warning":[],"fxLink":"https://not-qweather.example/warning"}"#.utf8))
        XCTAssertNil(otherHost.detailURL)
    }

    func testDefaultWeatherNeedsNoCredentialAndDoesNotInventNoWarnings() async throws {
        let client = CampusWeatherClient { request in
            XCTAssertEqual(request.url?.host, "api.open-meteo.com")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            let query = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems
            XCTAssertEqual(query?.first(where: { $0.name == "latitude" })?.value, "30.9")
            return Self.response(Self.freeJSON, url: try XCTUnwrap(request.url))
        }
        let report = try await client.fetch(location: .xuancheng)
        XCTAssertEqual(report.source, "Open-Meteo")
        XCTAssertEqual(report.observation.temperature, 21.5)
        XCTAssertEqual(report.warningURL, CampusWeatherLocation.xuancheng.officialWarningURL)
        guard case .unavailable = report.warnings else { return XCTFail("No API access cannot mean no warnings") }
    }

    func testConfiguredQWeatherRequestsAndLinksMatchUpstream() async throws {
        let configuration = try QWeatherConfiguration(apiBaseURL: URL(string: "https://test.qweatherapi.com/v7/")!, bearerToken: "test-only-jwt")
        let client = CampusWeatherClient(qWeather: configuration) { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-only-jwt")
            XCTAssertEqual(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "101220101")
            let payload = request.url?.path == "/v7/weather/now" ? Self.nowJSON : Self.warningJSON
            XCTAssertTrue(["/v7/weather/now", "/v7/warning/now"].contains(request.url?.path ?? ""))
            return Self.response(payload, url: try XCTUnwrap(request.url))
        }
        let report = try await client.fetch(location: .hefei)
        XCTAssertEqual(report.source, "和风天气 QWeather")
        guard case let .available(warnings) = report.warnings else { return XCTFail("Expected parsed warnings") }
        XCTAssertEqual(warnings.count, 1)
        XCTAssertEqual(report.detailURL, CampusWeatherLocation.hefei.officialWeatherURL)
        XCTAssertEqual(report.warningURL, CampusWeatherLocation.hefei.officialWarningURL)
    }

    func testWarningFailureDoesNotDiscardSuccessfulWeatherOrClaimNoWarnings() async throws {
        let configuration = try QWeatherConfiguration(apiBaseURL: URL(string: "https://test.qweatherapi.com/v7/")!, bearerToken: "test-only-jwt")
        let client = CampusWeatherClient(qWeather: configuration) { request in
            Self.response(request.url?.path == "/v7/weather/now" ? Self.nowJSON : "{}", url: try XCTUnwrap(request.url), status: request.url?.path == "/v7/weather/now" ? 200 : 503)
        }
        let report = try await client.fetch(location: .hefei)
        XCTAssertEqual(report.source, "和风天气 QWeather")
        XCTAssertEqual(report.observation.temperature, 19)
        guard case .unavailable = report.warnings else { return XCTFail("A failed request cannot mean no warnings") }
    }

    func testExpiredOptionalQWeatherAccessFallsBackToFreeCurrentWeather() async throws {
        let configuration = try QWeatherConfiguration(apiBaseURL: URL(string: "https://test.qweatherapi.com/v7/")!, bearerToken: "test-only-jwt")
        let client = CampusWeatherClient(qWeather: configuration) { request in
            let free = request.url?.host == "api.open-meteo.com"
            return Self.response(free ? Self.freeJSON : "{}", url: try XCTUnwrap(request.url), status: free ? 200 : 401)
        }
        let report = try await client.fetch(location: .hefei)
        XCTAssertEqual(report.source, "Open-Meteo")
        guard case .unavailable = report.warnings else { return XCTFail("Fallback has no warning feed") }
    }

    func testConfigurationRequiresHTTPSAndNoHeaderInjection() {
        XCTAssertThrowsError(try QWeatherConfiguration(apiBaseURL: URL(string: "http://test.qweatherapi.com/v7/")!, bearerToken: "test-only-jwt"))
        XCTAssertThrowsError(try QWeatherConfiguration(apiBaseURL: URL(string: "https://test.qweatherapi.com/v7/")!, bearerToken: "test\r\nX-Injected: value"))
    }

    private static func response(_ json: String, url: URL, status: Int = 200) -> (Data, URLResponse) {
        (Data(json.utf8), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
