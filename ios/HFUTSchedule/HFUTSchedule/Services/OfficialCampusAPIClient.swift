import Foundation
import Security

struct OfficialCourseSearchResult: Identifiable, Hashable {
    let id: Int
    let courseName: String
    let className: String?
    let code: String?
    let teachers: [String]
    let department: String?
    let credits: Double?
    let weeks: String?
    let schedule: String?
}

struct OfficialClassmate: Decodable, Identifiable, Hashable {
    let code: String
    let nameZh: String
    let className: String
    let gender: String
    let telephone: String?

    var id: String { code }

    private enum CodingKeys: String, CodingKey {
        case code, nameZh, className = "adminclass", gender, telephone
    }
}

struct OfficialClassroom: Decodable, Identifiable, Hashable {
    let id: Int
    let nameZh: String
    let floor: Int?
    let seatsForLesson: Int?
    let roomType: OfficialLocalizedName?
    let building: Building?

    struct Building: Decodable, Hashable {
        let nameZh: String?
        let campus: OfficialLocalizedName?
    }
}

struct OfficialFailRateRecord: Decodable, Identifiable, Hashable {
    let courseName: String
    let courseCode: String
    let terms: [Term]

    var id: String { "\(courseCode)|\(courseName)" }

    struct Term: Decodable, Hashable {
        let year: String
        let period: String
        let averageScore: Double
        let totalCount: Int
        let failCount: Int
        let successRate: Double

        private enum CodingKeys: String, CodingKey {
            case year = "xn", period = "xq", averageScore = "avgScore"
            case totalCount, failCount, successRate
        }
    }

    private enum CodingKeys: String, CodingKey {
        case courseName, courseCode = "courseMetaId", terms = "courseFailRateDTOList"
    }
}

struct OfficialLocalizedName: Decodable, Hashable {
    let nameZh: String?
}

final class OfficialCampusAPIClient: @unchecked Sendable {
    static let shared = OfficialCampusAPIClient()

    private let session: URLSession
    private let noRedirectSession: URLSession
    private let uniAppTokenAccount = "official-uniapp-id-token"
    private let communityTokenAccount = "official-community-token"

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = .shared
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.timeoutIntervalForRequest = 40
        configuration.timeoutIntervalForResource = 60
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 HFUTSchedule-iOS"
        ]
        session = URLSession(configuration: configuration)
        noRedirectSession = URLSession(
            configuration: configuration,
            delegate: OfficialNoRedirectDelegate.shared,
            delegateQueue: nil
        )
    }

    var hasUniAppToken: Bool { SecureTokenStore.read(uniAppTokenAccount) != nil }
    var hasCommunityToken: Bool { SecureTokenStore.read(communityTokenAccount) != nil }

    @discardableResult
    func loginUniApp(username: String, password: String) async throws -> String {
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !password.isEmpty else {
            throw OfficialCampusAPIError.uniAppAuthenticationRequired
        }
        let encrypted = try OfficialRSA.encrypt(password)
        var components = URLComponents(string: "https://jwglapp.hfut.edu.cn/token/password/passwordLogin")!
        components.queryItems = [
            URLQueryItem(name: "username", value: username.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(name: "password", value: encrypted),
            URLQueryItem(name: "appId", value: "APP_ID"),
            URLQueryItem(name: "deviceId", value: "DEVICE_ID")
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        let (data, response) = try await data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            let message = (try? JSONDecoder().decode(UniAppLoginFailure.self, from: data).message) ?? "HTTP \(response.statusCode)"
            throw OfficialCampusAPIError.loginFailed(message)
        }
        guard let token = try? JSONDecoder().decode(UniAppLoginEnvelope.self, from: data).data.idToken,
              !token.isEmpty else {
            throw OfficialCampusAPIError.invalidData("合工大教务未返回登录令牌")
        }
        try SecureTokenStore.write(token, account: uniAppTokenAccount)
        return token
    }

    func fetchClassmates(lessonID: Int) async throws -> [OfficialClassmate] {
        guard let token = SecureTokenStore.read(uniAppTokenAccount) else {
            throw OfficialCampusAPIError.uniAppAuthenticationRequired
        }
        let url = URL(string: "https://jwglapp.hfut.edu.cn/eams-micro-server/api/v1/lesson/student/class-mates/\(lessonID)")!
        let data = try await authorizedUniAppData(url: url, token: token)
        return try JSONDecoder().decode(ClassmatesEnvelope.self, from: data).data ?? []
    }

    func searchClassrooms(name: String, page: Int = 1) async throws -> [OfficialClassroom] {
        guard let token = SecureTokenStore.read(uniAppTokenAccount) else {
            throw OfficialCampusAPIError.uniAppAuthenticationRequired
        }
        var components = URLComponents(string: "https://jwglapp.hfut.edu.cn/eams-micro-server/api/v1/lesson/room/searchRooms")!
        components.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "queryPage__", value: "\(page),30")
        ]
        let data = try await authorizedUniAppData(url: components.url!, token: token)
        return try JSONDecoder().decode(ClassroomEnvelope.self, from: data).data.data
    }

    @discardableResult
    func refreshCommunityToken() async throws -> String {
        CampusSessionStore.shared.restoreToSharedStorage()
        var cas = URLComponents(string: "https://cas.hfut.edu.cn/cas/login")!
        cas.queryItems = [URLQueryItem(name: "service", value: "https://community.hfut.edu.cn/")]
        let (_, response) = try await noRedirectSession.data(for: URLRequest(url: cas.url!))
        guard let http = response as? HTTPURLResponse,
              (300..<400).contains(http.statusCode),
              let location = http.value(forHTTPHeaderField: "Location"),
              let ticket = URLComponents(string: location)?.queryItems?.first(where: { $0.name == "ticket" })?.value else {
            throw OfficialCampusAPIError.communityAuthenticationRequired
        }

        var validate = URLComponents(string: "https://community.hfut.edu.cn/api/sys/cas/client/validateLogin")!
        validate.queryItems = [
            URLQueryItem(name: "service", value: "https://community.hfut.edu.cn/"),
            URLQueryItem(name: "ticket", value: ticket)
        ]
        let (data, validateResponse) = try await data(for: URLRequest(url: validate.url!))
        guard (200..<300).contains(validateResponse.statusCode),
              let token = try? JSONDecoder().decode(CommunityLoginEnvelope.self, from: data).result.token,
              !token.isEmpty else {
            throw OfficialCampusAPIError.communityAuthenticationRequired
        }
        try SecureTokenStore.write(token, account: communityTokenAccount)
        CampusSessionStore.shared.persist(HTTPCookieStorage.shared.cookies ?? [])
        return token
    }

    func fetchFailRates(courseName: String, page: Int = 1, retrying: Bool = false) async throws -> [OfficialFailRateRecord] {
        let token: String
        if let saved = SecureTokenStore.read(communityTokenAccount) {
            token = saved
        } else {
            token = try await refreshCommunityToken()
        }
        var components = URLComponents(string: "https://community.hfut.edu.cn/api/business/coursefailrate/list")!
        components.queryItems = [
            URLQueryItem(name: "courseName", value: courseName),
            URLQueryItem(name: "pageNo", value: String(page)),
            URLQueryItem(name: "pageSize", value: "30")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(token, forHTTPHeaderField: "X-Access-Token")
        let (data, response) = try await data(for: request)
        if response.statusCode == 401 || response.statusCode == 403 {
            SecureTokenStore.delete(communityTokenAccount)
            throw OfficialCampusAPIError.communityAuthenticationRequired
        }
        guard (200..<300).contains(response.statusCode) else { throw OfficialCampusAPIError.http(response.statusCode) }
        do {
            return try JSONDecoder().decode(FailRateEnvelope.self, from: data).result.records
        } catch {
            guard !retrying else { throw error }
            SecureTokenStore.delete(communityTokenAccount)
            _ = try await refreshCommunityToken()
            return try await fetchFailRates(courseName: courseName, page: page, retrying: true)
        }
    }

    private func authorizedUniAppData(url: URL, token: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(token, forHTTPHeaderField: "Authorization")
        let (data, response) = try await data(for: request)
        if response.statusCode == 401 || response.statusCode == 403 {
            SecureTokenStore.delete(uniAppTokenAccount)
            throw OfficialCampusAPIError.uniAppAuthenticationRequired
        }
        guard (200..<300).contains(response.statusCode) else { throw OfficialCampusAPIError.http(response.statusCode) }
        return data
    }

    private func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw OfficialCampusAPIError.invalidResponse }
        return (data, response)
    }
}

enum OfficialCampusAPIError: LocalizedError {
    case invalidResponse
    case invalidData(String)
    case http(Int)
    case loginFailed(String)
    case uniAppAuthenticationRequired
    case communityAuthenticationRequired

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "校方接口返回了无法识别的响应。"
        case .invalidData(let message): message
        case .http(let code): "校方接口请求失败（HTTP \(code)）。"
        case .loginFailed(let message): "合工大教务登录失败：\(message)"
        case .uniAppAuthenticationRequired: "此功能使用校方“合工大教务”API，需要教务系统密码完成一次令牌登录。"
        case .communityAuthenticationRequired: "智慧社区令牌未生效，请在“选项 → 前往安全登录”重新完成统一身份认证。"
        }
    }
}

private struct UniAppLoginEnvelope: Decodable { let data: DataValue; struct DataValue: Decodable { let idToken: String } }
private struct UniAppLoginFailure: Decodable { let message: String }
private struct ClassmatesEnvelope: Decodable { let data: [OfficialClassmate]? }
private struct ClassroomEnvelope: Decodable { let data: Page; struct Page: Decodable { let data: [OfficialClassroom] } }
private struct CommunityLoginEnvelope: Decodable { let result: ResultValue; struct ResultValue: Decodable { let token: String? } }
private struct FailRateEnvelope: Decodable { let result: ResultValue; struct ResultValue: Decodable { let records: [OfficialFailRateRecord] } }

private enum SecureTokenStore {
    private static let service = "com.xiaozhangwangxue.hfutschedule.official-api"

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String, account: String) throws {
        delete(account)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(value.utf8)
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw OfficialCampusAPIError.invalidData("安全存储令牌失败（\(status)）") }
    }

    static func delete(_ account: String) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ] as CFDictionary)
    }
}

private enum OfficialRSA {
    private static let publicKey = "MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCFY5N+9UX+0BF+xz1svFguI4CIDvmQTfINkOZ1HOO3ltBNHGQTUirUPQTyEph/+q/l8b16YYw3I2fyTH6y15s3tHf5jMei+R/20jFRGo5udwVJUwq/RozKQIRzCtPYkXG4YWBnHKhXalZ5K2fhd5i/QtB016nVugH/7eiBDWbKVwIDAQAB"

    static func encrypt(_ plaintext: String) throws -> String {
        guard let x509 = Data(base64Encoded: publicKey),
              let rawKey = stripSubjectPublicKeyInfo(x509) else {
            throw OfficialCampusAPIError.invalidData("教务公钥无效")
        }
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: 1024
        ]
        var createError: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(rawKey as CFData, attributes as CFDictionary, &createError) else {
            if let error = createError?.takeRetainedValue() { throw error }
            throw OfficialCampusAPIError.invalidData("无法载入教务公钥")
        }
        var encryptionError: Unmanaged<CFError>?
        guard let encrypted = SecKeyCreateEncryptedData(key, .rsaEncryptionPKCS1, Data(plaintext.utf8) as CFData, &encryptionError) else {
            if let error = encryptionError?.takeRetainedValue() { throw error }
            throw OfficialCampusAPIError.invalidData("教务密码加密失败")
        }
        return (encrypted as Data).base64EncodedString()
    }

    private static func stripSubjectPublicKeyInfo(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard let bitString = bytes.indices.first(where: { index in
            index + 4 < bytes.count && bytes[index] == 0x03 && bytes[index + 3] == 0x00 && bytes[index + 4] == 0x30
        }) else { return nil }
        return Data(bytes[(bitString + 4)...])
    }
}

private final class OfficialNoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = OfficialNoRedirectDelegate()
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
