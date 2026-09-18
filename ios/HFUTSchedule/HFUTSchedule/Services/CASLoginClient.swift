import CommonCrypto
import Foundation

struct CASLoginPreparation {
    let execution: String
    let needsCaptcha: Bool
    let captchaImageData: Data?
}

final class CASLoginClient: @unchecked Sendable {
    // CAS only accepts the service identifier registered by HFUT. Although the
    // academic portal now supports HTTPS, the registered CAS callback remains
    // HTTP and changing its scheme produces the CAS "unauthorized service" page.
    static let service = "http://jxglstu.hfut.edu.cn/eams5-student/neusoft-sso/login"
    private static let webVPNRoot = "https://webvpn.hfut.edu.cn/"
    private static let webVPNCASPrefix = "http/77726476706e69737468656265737421f3f652d22f367d44300d8db9d6562d/cas/"
    private static let webVPNAcademicLogin = "https://webvpn.hfut.edu.cn/http/77726476706e69737468656265737421faef469034247d1e760e9cb8d6502720ede479/eams5-student/neusoft-sso/login"

    private let mode: AcademicConnectionMode
    private let cookieStorage: HTTPCookieStorage
    private let session: URLSession
    private var webVPNFlavoring: String?
    // Keep the three values separately and assemble them in the same order as
    // the Android client. CAS deliberately creates SESSION and JSESSIONID in
    // two independent requests; allowing a browser cookie jar to merge those
    // preparatory requests changes the server-side login flow.
    private var directLoginCookieHeader: String?
    private var directCaptchaCookieHeader: String?

    init(mode: AcademicConnectionMode = .direct) {
        self.mode = mode
        cookieStorage = .shared
        let configuration = URLSessionConfiguration.ephemeral
        // Every Cookie header is attached explicitly below. This mirrors the
        // Retrofit implementation and prevents URLSession from silently
        // replacing one of CAS's independently issued session cookies.
        configuration.httpCookieStorage = nil
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 20
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/118.0.0.0 Safari/537.36 Edg/118.0.2088.17"
        ]
        session = URLSession(configuration: configuration, delegate: NoRedirectDelegate.shared, delegateQueue: nil)
    }

    func prepare(includeCaptcha: Bool = true) async throws -> CASLoginPreparation {
        // A persisted TGC makes /cas/login immediately redirect to a service
        // ticket, so there is no login form (and therefore no `execution`).
        // Entering this screen means the user explicitly requested a fresh
        // authentication flow; clear only CAS cookies, retaining WebVPN and all
        // service-specific sessions.
        CampusSessionStore.shared.removeCookies(forDomainSuffix: "cas.hfut.edu.cn")
        directLoginCookieHeader = nil
        directCaptchaCookieHeader = nil
        webVPNFlavoring = nil

        // Original Android flow starts these as independent Retrofit calls:
        //   1. GET /cas/login -> execution + SESSION
        //   2. GET /cas/checkInitParams -> JSESSIONID + LOGIN_FLAVORING
        let (execution, loginCookies) = try await fetchExecution()
        let needsCaptcha: Bool

        if mode == .webVPN {
            let (_, ticketResponse) = try await data(
                for: URLRequest(url: URL(string: Self.webVPNRoot + "login?cas_login=true")!),
                accepted: 200..<400
            )
            guard vpnTicket(from: ticketResponse) != nil else { throw CASLoginError.missingWebVPNTicket }

            let initURL = URL(string: Self.webVPNRoot + Self.webVPNCASPrefix + "checkInitParams")!
            let (initData, _) = try await data(for: URLRequest(url: initURL), accepted: 200..<300)
            needsCaptcha = (try? JSONDecoder().decode(FlavorResponse.self, from: initData).needCaptcha) ?? false

            let cookieURL = URL(string: Self.webVPNRoot + "wengine-vpn/cookie?method=get&host=cas.hfut.edu.cn&scheme=http&path=/cas/login")!
            let (cookieData, _) = try await data(for: URLRequest(url: cookieURL), accepted: 200..<300)
            guard let cookieText = String(data: cookieData, encoding: .utf8),
                  let flavoring = Self.firstMatch(in: cookieText, pattern: #"LOGIN_FLAVORING=([^;\s]+)"#) else {
                throw CASLoginError.missingFlavoring
            }
            webVPNFlavoring = flavoring
        } else {
            let keyURL = URL(string: "https://cas.hfut.edu.cn/cas/checkInitParams")!
            let (keyData, keyResponse) = try await data(
                for: URLRequest(url: keyURL),
                accepted: 200..<300,
                includeStoredCookies: false
            )
            needsCaptcha = (try? JSONDecoder().decode(FlavorResponse.self, from: keyData).needCaptcha) ?? false
            let keyCookies = responseCookies(from: keyResponse)
            guard let flavoring = cookieValue(named: "LOGIN_FLAVORING", in: keyCookies), !flavoring.isEmpty else {
                throw CASLoginError.missingFlavoring
            }
            guard let loginSession = cookieValue(named: "SESSION", in: loginCookies), !loginSession.isEmpty else {
                throw CASLoginError.missingLoginSession
            }
            guard let jsession = cookieValue(named: "JSESSIONID", in: keyCookies), !jsession.isEmpty else {
                throw CASLoginError.missingJSession
            }
            directCaptchaCookieHeader = "JSESSIONID=\(jsession)"
            directLoginCookieHeader = [
                "SESSION=\(loginSession)",
                "JSESSIONID=\(jsession)",
                "LOGIN_FLAVORING=\(flavoring)"
            ].joined(separator: ";")
        }

        let captchaData = needsCaptcha && includeCaptcha ? try await fetchCaptcha() : nil
        return CASLoginPreparation(execution: execution, needsCaptcha: needsCaptcha, captchaImageData: captchaData)
    }

    private func fetchExecution() async throws -> (String, [HTTPCookie]) {
        let loginURL = try Self.directLoginURL()
        let (loginData, response) = try await data(
            for: URLRequest(url: loginURL),
            accepted: 200..<300,
            includeStoredCookies: false
        )
        guard let html = String(data: loginData, encoding: .utf8),
              let execution = Self.firstMatch(in: html, pattern: #"name=[\"']execution[\"'][^>]*value=[\"']([^\"']+)[\"']"#)
                ?? Self.firstMatch(in: html, pattern: #"value=[\"']([^\"']+)[\"'][^>]*name=[\"']execution[\"']"#) else {
            throw CASLoginError.missingExecution
        }
        return (execution, responseCookies(from: response))
    }

    func fetchCaptcha() async throws -> Data {
        let base = mode == .direct
            ? "https://cas.hfut.edu.cn/cas/vercode"
            : Self.webVPNRoot + Self.webVPNCASPrefix + "vercode"
        var components = URLComponents(string: base)!
        components.queryItems = [URLQueryItem(name: "timestamp", value: String(Int(Date().timeIntervalSince1970 * 1_000)))]
        var request = URLRequest(url: components.url!)
        if mode == .direct, let directCaptchaCookieHeader {
            request.setValue(directCaptchaCookieHeader, forHTTPHeaderField: "Cookie")
        }
        let (data, _) = try await data(for: request, accepted: 200..<300)
        return data
    }

    func login(username: String, password: String, captcha: String, execution: String) async throws -> [HTTPCookie] {
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CASLoginError.invalidCredentials("请输入学号")
        }
        guard !password.isEmpty else { throw CASLoginError.invalidCredentials("请输入信息门户密码") }
        let flavoring = mode == .direct
            ? directLoginCookieHeader.flatMap { Self.firstMatch(in: $0, pattern: #"LOGIN_FLAVORING=([^;]+)"#) }
            : webVPNFlavoring
        guard let flavoring else { throw CASLoginError.missingFlavoring }
        let encryptedPassword = try Self.encryptAES(password, key: flavoring)

        var request = URLRequest(url: try loginURL())
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        if mode == .direct {
            guard let directLoginCookieHeader else { throw CASLoginError.missingLoginSession }
            request.setValue(directLoginCookieHeader, forHTTPHeaderField: "Cookie")
        }
        request.httpBody = Self.formBody([
            ("username", username.trimmingCharacters(in: .whitespacesAndNewlines)),
            ("password", encryptedPassword),
            ("execution", execution),
            ("_eventId", "submit"),
            ("capcha", captcha.trimmingCharacters(in: .whitespacesAndNewlines))
        ])

        let (failureBody, response) = try await data(for: request, accepted: 200..<402)
        if response.statusCode == 401 {
            let text = String(data: failureBody, encoding: .utf8) ?? ""
            let reason = text.localizedCaseInsensitiveContains("captcha") || text.contains("验证码")
                ? "验证码错误或已过期"
                : "信息门户账号或密码错误"
            throw CASLoginError.invalidCredentials(reason)
        }
        guard (200..<400).contains(response.statusCode) else {
            throw CASLoginError.http(response.statusCode)
        }

        let nextStartURL: URL?
        if mode == .webVPN {
            // 原版在 WebVPN 模式下把代理 CAS 的 HTTP 200 视为成功，随后再访问
            // 代理教务登录入口使虚拟 Cookie 生效；这里不能强制要求 302 ticket。
            guard response.statusCode == 200 || response.statusCode == 302 || response.statusCode == 303 else {
                throw CASLoginError.invalidCredentials("WebVPN CAS 登录失败，请检查账号、密码或验证码")
            }
            nextStartURL = URL(string: Self.webVPNAcademicLogin)
        } else {
            guard response.statusCode == 302 || response.statusCode == 303,
                  let locationText = response.value(forHTTPHeaderField: "Location"),
                  locationText.contains("ticket=") else {
                throw CASLoginError.invalidCredentials("CAS 未返回登录票据，请检查账号、密码或验证码")
            }
            nextStartURL = URL(string: locationText, relativeTo: response.url)?.absoluteURL
        }
        if let nextStartURL { try await followServiceRedirects(from: nextStartURL) }

        if mode == .webVPN {
            let vpnCookies = cookieStorage.cookies(for: URL(string: Self.webVPNRoot)!) ?? []
            guard vpnCookies.contains(where: { $0.name == "wengine_vpn_ticketwebvpn_hfut_edu_cn" }) else {
                throw CASLoginError.missingWebVPNTicket
            }
            let allCookies = cookieStorage.cookies ?? vpnCookies
            CampusSessionStore.shared.persist(allCookies)
            return allCookies
        } else {
            // A SESSION cookie alone is not proof of authentication: the
            // academic server also issues an anonymous SESSION before sending
            // users to /login. Verify the same course-table 302 used by the
            // Android client, and obtain a fresh service ticket from the TGC
            // once if the first exchange did not establish the session.
            if try await !hasAuthenticatedAcademicSession() {
                try await refreshAcademicSessionFromTGC()
            }
            guard try await hasAuthenticatedAcademicSession() else {
                throw CASLoginError.missingAcademicSession
            }
            let academicCookies = cookieStorage.cookies(for: AcademicPortal.directAcademicRoot) ?? []
            guard academicCookies.contains(where: { $0.name == "SESSION" }) else {
                throw CASLoginError.missingAcademicSession
            }
            CampusSessionStore.shared.persist(cookieStorage.cookies ?? academicCookies)
            return academicCookies
        }
    }

    private func followServiceRedirects(from start: URL) async throws {
        var nextURL: URL? = start
        for _ in 0..<8 {
            guard let url = nextURL else { return }
            let (_, response) = try await data(for: URLRequest(url: url), accepted: 200..<400)
            guard (300..<400).contains(response.statusCode),
                  let location = response.value(forHTTPHeaderField: "Location") else { return }
            nextURL = URL(string: location, relativeTo: response.url ?? url)?.absoluteURL
        }
    }

    private func hasAuthenticatedAcademicSession() async throws -> Bool {
        let url = AcademicPortal.url("for-std/course-table", mode: .direct)
        let (body, response) = try await data(for: URLRequest(url: url), accepted: 200..<400)
        let location = response.value(forHTTPHeaderField: "Location") ?? ""
        if location.contains("/for-std/course-table/info/") { return true }
        let html = String(data: body, encoding: .utf8) ?? ""
        return html.range(of: #"course-table/info/\d+"#, options: .regularExpression) != nil
    }

    private func refreshAcademicSessionFromTGC() async throws {
        let (_, response) = try await data(for: URLRequest(url: try Self.directLoginURL()), accepted: 200..<400)
        guard (300..<400).contains(response.statusCode),
              let location = response.value(forHTTPHeaderField: "Location"),
              location.contains("ticket="),
              let ticketURL = URL(string: location, relativeTo: response.url)?.absoluteURL else {
            throw CASLoginError.missingAcademicSession
        }
        try await followServiceRedirects(from: ticketURL)
    }

    private func vpnTicket(from response: HTTPURLResponse?) -> String? {
        if let value = cookieStorage.cookies?.first(where: { $0.name == "wengine_vpn_ticketwebvpn_hfut_edu_cn" })?.value,
           !value.isEmpty { return value }
        guard let response else { return nil }
        return response.value(forHTTPHeaderField: "Set-Cookie")
            .flatMap { Self.firstMatch(in: $0, pattern: #"wengine_vpn_ticketwebvpn_hfut_edu_cn=([^;\s,]+)"#) }
    }

    private func loginFlavoring(from response: HTTPURLResponse?) -> String? {
        if let value = cookieStorage.cookies?.first(where: { $0.name == "LOGIN_FLAVORING" })?.value,
           !value.isEmpty { return value }
        guard let response,
              let headers = HTTPCookie.cookies(withResponseHeaderFields: response.allHeaderFields.reduce(into: [:]) {
                  guard let key = $1.key as? String, let value = $1.value as? String else { return }
                  $0[key] = value
              }, for: response.url ?? URL(string: "https://cas.hfut.edu.cn/")!) as [HTTPCookie]? else { return nil }
        return headers.first(where: { $0.name == "LOGIN_FLAVORING" })?.value
    }

    private func data(
        for originalRequest: URLRequest,
        accepted: Range<Int>,
        includeStoredCookies: Bool = true
    ) async throws -> (Data, HTTPURLResponse) {
        var request = originalRequest
        if includeStoredCookies,
           request.value(forHTTPHeaderField: "Cookie") == nil,
           let url = request.url {
            let cookies = cookieStorage.cookies(for: url) ?? []
            if !cookies.isEmpty {
                request.setValue(
                    cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; "),
                    forHTTPHeaderField: "Cookie"
                )
            }
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            let nsError = error as NSError
            let failingURL = (nsError.userInfo[NSURLErrorFailingURLStringErrorKey] as? String)
                ?? request.url?.absoluteString
                ?? "未知地址"
            throw CASLoginError.network(failingURL, error.localizedDescription)
        }
        guard let response = response as? HTTPURLResponse else { throw CASLoginError.invalidResponse }
        if let url = response.url {
            let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, item in
                guard let key = item.key as? String else { return }
                result[key] = String(describing: item.value)
            }
            let responseCookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)
            for cookie in responseCookies { cookieStorage.setCookie(cookie) }
            CampusSessionStore.shared.persist((cookieStorage.cookies ?? []) + responseCookies)
        }
        guard accepted.contains(response.statusCode) else { throw CASLoginError.http(response.statusCode) }
        return (data, response)
    }

    private func responseCookies(from response: HTTPURLResponse) -> [HTTPCookie] {
        let url = response.url ?? URL(string: "https://cas.hfut.edu.cn/")!
        let fields = response.allHeaderFields.reduce(into: [String: String]()) { result, item in
            guard let key = item.key as? String else { return }
            result[key] = String(describing: item.value)
        }
        let parsed = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
        if !parsed.isEmpty { return parsed }
        return cookieStorage.cookies(for: url) ?? []
    }

    private func cookieValue(named name: String, in cookies: [HTTPCookie]) -> String? {
        cookies.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })?.value
    }

    private func loginURL() throws -> URL {
        if mode == .webVPN {
            guard let url = URL(string: Self.webVPNRoot + Self.webVPNCASPrefix + "login?service=" + Self.service) else {
                throw CASLoginError.invalidResponse
            }
            return url
        }
        return try Self.directLoginURL()
    }

    private static func directLoginURL() throws -> URL {
        var components = URLComponents(string: "https://cas.hfut.edu.cn/cas/login")!
        components.queryItems = [URLQueryItem(name: "service", value: service)]
        guard let url = components.url else { throw CASLoginError.invalidResponse }
        return url
    }

    private static func formBody(_ fields: [(String, String)]) -> Data {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return fields.map { key, value in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(encodedKey)=\(encodedValue)"
        }.joined(separator: "&").data(using: .utf8)!
    }

    static func encryptAES(_ plaintext: String, key: String) throws -> String {
        let keyData = Data(key.utf8)
        guard [kCCKeySizeAES128, kCCKeySizeAES192, kCCKeySizeAES256].contains(keyData.count) else {
            throw CASLoginError.invalidEncryptionKey
        }
        let input = Data(plaintext.utf8)
        var output = Data(count: input.count + kCCBlockSizeAES128)
        let outputCapacity = output.count
        var outputLength = 0
        let status = output.withUnsafeMutableBytes { outputBytes in
            input.withUnsafeBytes { inputBytes in
                keyData.withUnsafeBytes { keyBytes in
                    CCCrypt(
                        CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding | kCCOptionECBMode),
                        keyBytes.baseAddress, keyData.count, nil,
                        inputBytes.baseAddress, input.count,
                        outputBytes.baseAddress, outputCapacity, &outputLength
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw CASLoginError.encryptionFailed(status) }
        output.removeSubrange(outputLength..<output.count)
        return output.base64EncodedString()
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private struct FlavorResponse: Decodable {
        let needCaptcha: Bool

        private enum CodingKeys: String, CodingKey {
            case needCaptcha = "vercode"
        }
    }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = NoRedirectDelegate()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

enum CASLoginError: LocalizedError {
    case invalidResponse
    case http(Int)
    case missingFlavoring
    case missingLoginSession
    case missingJSession
    case missingExecution
    case invalidEncryptionKey
    case encryptionFailed(CCCryptorStatus)
    case invalidCredentials(String)
    case missingAcademicSession
    case missingWebVPNTicket
    case network(String, String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "统一身份认证返回了无法识别的响应。"
        case .http(let code): "统一身份认证请求失败（HTTP \(code)）。"
        case .missingFlavoring: "未获取到 CAS 加密密钥，请刷新后重试。"
        case .missingLoginSession: "未获取到原版登录流程所需的 CAS SESSION，请刷新后重试。"
        case .missingJSession: "未获取到原版登录流程所需的 CAS JSESSIONID，请刷新后重试。"
        case .missingExecution: "未获取到 CAS 登录参数，请刷新后重试。"
        case .invalidEncryptionKey: "CAS 返回了无效的加密密钥。"
        case .encryptionFailed(let status): "密码加密失败（\(status)）。"
        case .invalidCredentials(let message): message
        case .missingAcademicSession: "CAS 登录成功，但教务系统没有返回 SESSION。请确认当前网络可以访问教务系统。"
        case .missingWebVPNTicket: "未获取到 WebVPN 会话，请重新打开校外访问并重试。"
        case .network(let url, let message): "访问校方服务失败：\(message)\n\n地址：\(url)"
        }
    }
}
