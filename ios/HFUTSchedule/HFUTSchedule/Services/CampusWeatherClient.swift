import Foundation

enum CampusWeatherLocation: CaseIterable {
    case hefei, xuancheng

    var cityName: String { self == .hefei ? "合肥" : "宣城" }
    var qWeatherLocationID: String { self == .hefei ? "101220101" : "101221401" }
    var coordinates: (latitude: Double, longitude: Double) {
        self == .hefei ? (31.77, 117.20) : (30.90, 118.71)
    }
    private var pageSlug: String { self == .hefei ? "hefei-101220101" : "xuancheng-101221401" }
    var officialWeatherURL: URL { URL(string: "https://www.qweather.com/weather/\(pageSlug).html")! }
    var officialWarningURL: URL { URL(string: "https://www.qweather.com/severe-weather/\(pageSlug).html")! }
}

struct CampusWeatherObservation: Equatable {
    let temperature: Double
    let apparent: Double
    let humidity: Int
    let condition: String
    let symbol: String
    let windDescription: String
}

struct CampusWeatherWarning: Decodable, Identifiable, Equatable {
    let title: String
    let typeName: String
    let text: String
    var id: String { title + "|" + typeName + "|" + text }
}

enum CampusWeatherWarningState: Equatable {
    /// An empty list means a successful API response explicitly contained no warnings.
    case available([CampusWeatherWarning])
    /// Failure or no configured credentials must never be presented as “no warnings”.
    case unavailable(String)
}

struct CampusWeatherReport: Equatable {
    let observation: CampusWeatherObservation
    let source: String
    let detailURL: URL
    let warningURL: URL
    let warnings: CampusWeatherWarningState
}

enum CampusWeatherError: LocalizedError, Equatable {
    case invalidConfiguration
    case httpStatus(Int)
    case providerStatus(String)
    case invalidObservation

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "和风天气配置无效。"
        case let .httpStatus(status): "天气服务请求失败（\(status)）。"
        case let .providerStatus(status): "天气服务返回状态 \(status)。"
        case .invalidObservation: "天气服务返回了无法读取的数据。"
        }
    }
}

/// Optional configuration supplied by the app integrator using their own QWeather account.
/// No upstream signing credential is copied, and this client never discovers machine secrets.
struct QWeatherConfiguration {
    let apiBaseURL: URL
    let bearerToken: String

    init(apiBaseURL: URL, bearerToken: String) throws {
        let token = bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard apiBaseURL.scheme?.lowercased() == "https", apiBaseURL.host != nil,
              apiBaseURL.user == nil, apiBaseURL.password == nil,
              apiBaseURL.query == nil, apiBaseURL.fragment == nil,
              !token.isEmpty, token.rangeOfCharacter(from: .newlines) == nil else {
            throw CampusWeatherError.invalidConfiguration
        }
        self.apiBaseURL = apiBaseURL
        self.bearerToken = token
    }
}

struct CampusWeatherClient {
    typealias Transport = (URLRequest) async throws -> (Data, URLResponse)
    private let transport: Transport
    private let qWeather: QWeatherConfiguration?

    init(qWeather: QWeatherConfiguration? = nil, session: URLSession = .shared) {
        self.qWeather = qWeather
        transport = { try await session.data(for: $0) }
    }

    init(qWeather: QWeatherConfiguration? = nil, transport: @escaping Transport) {
        self.qWeather = qWeather
        self.transport = transport
    }

    func fetch(location: CampusWeatherLocation) async throws -> CampusWeatherReport {
        if let qWeather {
            do { return try await fetchQWeather(location: location, configuration: qWeather) }
            catch is CancellationError { throw CancellationError() }
            catch {
                try Task.checkCancellation()
                // Keep ordinary users' weather available even if optional QWeather access expires.
                return try await fetchOpenMeteo(
                    location: location,
                    warningStatus: "和风天气连接未成功，请打开官方预警页查看当前预警。"
                )
            }
        }
        return try await fetchOpenMeteo(
            location: location,
            warningStatus: "当前预警请打开和风天气官方页面查看。"
        )
    }

    private func fetchOpenMeteo(location: CampusWeatherLocation, warningStatus: String) async throws -> CampusWeatherReport {
        var url = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        url.queryItems = [
            .init(name: "latitude", value: String(location.coordinates.latitude)),
            .init(name: "longitude", value: String(location.coordinates.longitude)),
            .init(name: "current", value: "temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m"),
            .init(name: "timezone", value: "Asia/Shanghai")
        ]
        let data = try await request(URLRequest(url: url.url!))
        let observation = try JSONDecoder().decode(OpenMeteoResponse.self, from: data).current
        return CampusWeatherReport(
            observation: observation.value,
            source: "Open-Meteo",
            detailURL: location.officialWeatherURL,
            warningURL: location.officialWarningURL,
            warnings: .unavailable(warningStatus)
        )
    }

    private func fetchQWeather(location: CampusWeatherLocation, configuration: QWeatherConfiguration) async throws -> CampusWeatherReport {
        let nowData = try await request(qWeatherRequest(path: "weather/now", location: location, configuration: configuration))
        let now = try QWeatherPayloadDecoder.now(from: nowData)
        var warningURL = location.officialWarningURL
        let warningState: CampusWeatherWarningState
        do {
            let data = try await request(qWeatherRequest(path: "warning/now", location: location, configuration: configuration))
            let warning = try QWeatherPayloadDecoder.warnings(from: data)
            warningURL = warning.detailURL ?? warningURL
            warningState = .available(warning.items)
        } catch is CancellationError { throw CancellationError() }
        catch {
            try Task.checkCancellation()
            warningState = .unavailable("预警读取失败，请打开官方预警页查看。")
        }
        return CampusWeatherReport(
            observation: now.observation,
            source: "和风天气 QWeather",
            detailURL: now.detailURL ?? location.officialWeatherURL,
            warningURL: warningURL,
            warnings: warningState
        )
    }

    private func qWeatherRequest(path: String, location: CampusWeatherLocation, configuration: QWeatherConfiguration) -> URLRequest {
        var url = URLComponents(url: configuration.apiBaseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        url.queryItems = [.init(name: "location", value: location.qWeatherLocationID)]
        var result = URLRequest(url: url.url!)
        result.setValue("Bearer \(configuration.bearerToken)", forHTTPHeaderField: "Authorization")
        return result
    }

    private func request(_ request: URLRequest) async throws -> Data {
        var request = request
        request.timeoutInterval = 20
        let (data, response) = try await transport(request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw CampusWeatherError.invalidObservation }
        guard (200..<300).contains(http.statusCode) else { throw CampusWeatherError.httpStatus(http.statusCode) }
        return data
    }

    private struct OpenMeteoResponse: Decodable {
        let current: Current
        struct Current: Decodable {
            let temperature_2m: Double
            let apparent_temperature: Double
            let relative_humidity_2m: Int
            let weather_code: Int
            let wind_speed_10m: Double
            var value: CampusWeatherObservation {
                let condition: String
                let symbol: String
                switch weather_code {
                case 0: (condition, symbol) = ("晴", "sun.max.fill")
                case 1...3: (condition, symbol) = ("多云", "cloud.sun.fill")
                case 45...48: (condition, symbol) = ("雾", "cloud.fog.fill")
                case 51...67, 80...82: (condition, symbol) = ("雨", "cloud.rain.fill")
                case 71...77, 85...86: (condition, symbol) = ("雪", "cloud.snow.fill")
                case 95...99: (condition, symbol) = ("雷暴", "cloud.bolt.rain.fill")
                default: (condition, symbol) = ("天气", "cloud.fill")
                }
                return .init(
                    temperature: temperature_2m, apparent: apparent_temperature,
                    humidity: relative_humidity_2m, condition: condition, symbol: symbol,
                    windDescription: "风速 \(wind_speed_10m.formatted(.number.precision(.fractionLength(1)))) km/h"
                )
            }
        }
    }
}

/// Mirrors upstream QWeather now/warning envelopes, including the newly surfaced fxLink.
enum QWeatherPayloadDecoder {
    struct NowResult { let observation: CampusWeatherObservation; let detailURL: URL? }
    struct WarningResult { let items: [CampusWeatherWarning]; let detailURL: URL? }

    static func now(from data: Data) throws -> NowResult {
        try validate(JSONDecoder().decode(StatusEnvelope.self, from: data).code)
        let result = try JSONDecoder().decode(NowEnvelope.self, from: data)
        guard let temperature = Double(result.now.temp),
              let apparent = Double(result.now.feelsLike),
              let humidity = Int(result.now.humidity), (0...100).contains(humidity) else {
            throw CampusWeatherError.invalidObservation
        }
        let code = Int(result.now.icon) ?? 999
        let symbol: String
        switch code {
        case 100, 150: symbol = "sun.max.fill"
        case 101...153: symbol = "cloud.sun.fill"
        case 300...399: symbol = "cloud.rain.fill"
        case 400...499: symbol = "cloud.snow.fill"
        case 500...515: symbol = "cloud.fog.fill"
        default: symbol = "cloud.fill"
        }
        return .init(
            observation: .init(
                temperature: temperature, apparent: apparent, humidity: humidity,
                condition: result.now.text, symbol: symbol,
                windDescription: "\(result.now.windDir) · \(result.now.windScale)级"
            ),
            detailURL: officialDetailURL(result.fxLink)
        )
    }

    static func warnings(from data: Data) throws -> WarningResult {
        try validate(JSONDecoder().decode(StatusEnvelope.self, from: data).code)
        let result = try JSONDecoder().decode(WarningEnvelope.self, from: data)
        return .init(items: result.warning, detailURL: officialDetailURL(result.fxLink))
    }

    private static func validate(_ status: String?) throws {
        if let status, status != "200" { throw CampusWeatherError.providerStatus(status) }
    }

    private static func officialDetailURL(_ value: String?) -> URL? {
        guard let value, var components = URLComponents(string: value),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              let host = components.host?.lowercased(), host == "qweather.com" || host.hasSuffix(".qweather.com"),
              components.user == nil, components.password == nil else { return nil }
        components.scheme = "https"
        return components.url
    }

    private struct NowEnvelope: Decodable {
        let now: Now
        let fxLink: String?
        struct Now: Decodable {
            let temp: String; let feelsLike: String; let humidity: String
            let text: String; let icon: String; let windDir: String; let windScale: String
        }
    }
    private struct WarningEnvelope: Decodable {
        let warning: [CampusWeatherWarning]
        let fxLink: String?
    }
    private struct StatusEnvelope: Decodable { let code: String? }
}
