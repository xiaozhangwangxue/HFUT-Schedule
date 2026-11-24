import AppIntents
import Foundation
import CoreFoundation

enum CampusNetworkRegion: String, AppEnum, CaseIterable {
    case hefei, xuancheng
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "校园网校区"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [.hefei: "合肥校区", .xuancheng: "宣城校区"]
    var servers: [URL] {
        (self == .hefei ? ["http://172.16.200.11/"] : ["http://172.18.3.3/", "http://172.18.2.2/"]).compactMap(URL.init(string:))
    }
}

enum CampusNetworkLoginError: LocalizedError {
    case credentialsRequired
    var errorDescription: String? { "请先在 App 内同步学籍，并在网络设置中设置校园网密码（宣城使用一卡通密码）。" }
}

struct CampusNetworkLoginResult: Identifiable, Equatable {
    let server: String
    let succeeded: Bool
    let message: String
    var id: String { server }
}

struct CampusNetworkLoginClient {
    static func request(server: URL, username: String, password: String, region: CampusNetworkRegion) -> URLRequest {
        var request = URLRequest(url: server.appendingPathComponent("0.htm"))
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        request.httpBody = [("DDDDD", username), ("upass", password), ("0MKKey", region == .hefei ? "123" : "宣州Login")]
            .map { key, value in key + "=" + (value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "") }.joined(separator: "&").data(using: .utf8)
        return request
    }
    static func accepted(_ html: String) -> Bool { html.contains("成功") && !html.contains("已使用") && !html.contains("失败") }

    func login(region: CampusNetworkRegion, username: String, password: String,
               session: URLSession = .shared) async -> [CampusNetworkLoginResult] {
        var results: [CampusNetworkLoginResult] = []
        for server in region.servers {
            do {
                let (data, response) = try await session.data(for: Self.request(server: server, username: username, password: password, region: region))
                guard let http = response as? HTTPURLResponse, http.url?.host == server.host, (200..<300).contains(http.statusCode) else {
                    results.append(CampusNetworkLoginResult(server: server.host!, succeeded: false, message: "校园网未确认登录，请使用网页登录查看状态。")); continue
                }
                let gb = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
                let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: gb) ?? ""
                let success = Self.accepted(html)
                results.append(CampusNetworkLoginResult(server: server.host!, succeeded: success,
                    message: success ? "校方已确认登录成功" : "响应未确认成功，可能密码错误、已在其它设备使用，或不在对应校园网。"))
            } catch {
                results.append(CampusNetworkLoginResult(server: server.host!, succeeded: false,
                    message: "连接失败或超时，请连接对应校区校园 Wi-Fi 后重试。"))
            }
        }
        return results
    }

    @MainActor static func savedCredentials(region: CampusNetworkRegion, info: AcademicStudentInfo?) throws -> (String, String) {
        let credentials = try LifeCredentialPolicy.networkCredentials(xuancheng: region == .xuancheng)
        return (credentials.username, credentials.password)
    }
}

struct LoginCampusNetworkIntent: AppIntent {
    static var title: LocalizedStringResource = "登录校园网"
    static var description = IntentDescription("直接使用设备内已配置的校园网凭据登录对应校区，无需打开网页登录页。需连接校园网。")
    @Parameter(title: "校区", default: .hefei) var region: CampusNetworkRegion
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let (username, password) = try CampusNetworkLoginClient.savedCredentials(region: region, info: AcademicStudentStore().info)
        let results = await CampusNetworkLoginClient().login(region: region, username: username, password: password)
        let message = results.map { "\($0.server)：\($0.message)" }.joined(separator: "\n")
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}
