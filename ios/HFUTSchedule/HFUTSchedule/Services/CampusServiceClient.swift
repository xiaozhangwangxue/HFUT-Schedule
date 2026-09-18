import Foundation
import Security
import CryptoKit

struct HuiXinCard: Identifiable, Hashable {
    let account: String
    let name: String
    let balance: Double
    let unsettledAmount: Double
    let autoTransferLimit: Double
    let autoTransferAmount: Double

    var id: String { account }
}

struct SecondClassActivity: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let module: String
    let sponsor: String
    let peopleNum: Int
    let beginTime: String
    let endTime: String
    let activePhoto: String
    let form: String
    let campus: Int
    let keynoteSpeaker: String?
    let theVenue: String?
}

struct ShowerProfile: Identifiable, Hashable {
    let phone: String
    let name: String
    let balance: Double
    let giftedBalance: Double
    let loginCode: String

    var id: String { phone }
}

struct LaundryLocation: Decodable, Identifiable, Hashable {
    let id: Int64
    let name: String
    let address: String
    let workTime: String
    let categoryCodeList: [String]
    let enableReserve: Bool
    let reserveNum: Int
    let idleCount: Int
}

struct LaundryDevice: Decodable, Identifiable, Hashable {
    let id: Int64
    let name: String
    let floorCode: String?
    let state: Int
    let finishTime: String?
    let enableReserve: Bool
    let reserveNum: Int

    var stateText: String {
        if let finishDate, finishDate > Date() { return "占用" }
        return switch state {
        case 1: "空闲"
        case 2: "占用"
        case 3: "离线/故障"
        default: "未知"
        }
    }

    var finishDate: Date? {
        guard let finishTime, !finishTime.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy/MM/dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss"] {
            formatter.dateFormat = format
            if let value = formatter.date(from: finishTime) { return value }
        }
        return ISO8601DateFormatter().date(from: finishTime)
    }

    var remainingUsageText: String? {
        guard let finishDate else { return nil }
        let seconds = Int(finishDate.timeIntervalSinceNow)
        guard seconds > 0 else { return "本次使用已结束" }
        let minutes = max(1, Int(ceil(Double(seconds) / 60)))
        if minutes >= 60 {
            return "预计剩余 \(minutes / 60) 小时 \(minutes % 60) 分钟"
        }
        return "预计剩余 \(minutes) 分钟"
    }

    var floorText: String {
        guard let floorCode, !floorCode.isEmpty else { return "未标注楼层" }
        return "\(floorCode) 楼"
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, floorCode, state, finishTime, enableReserve, reserveNum
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int64.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        floorCode = try values.decodeIfPresent(String.self, forKey: .floorCode)
        state = try values.decode(Int.self, forKey: .state)
        finishTime = try values.decodeIfPresent(String.self, forKey: .finishTime)
        enableReserve = try values.decodeIfPresent(Bool.self, forKey: .enableReserve) ?? false
        // The live HaiLe response stopped returning reserveNum for devices in
        // 2026. Treat an omitted field as zero instead of discarding all data.
        reserveNum = try values.decodeIfPresent(Int.self, forKey: .reserveNum) ?? 0
    }
}

struct HuiXinSelectionOption: Decodable, Identifiable, Hashable {
    let name: String
    let value: String
    var id: String { value }
}

struct LibraryStatusSummary: Hashable {
    var bookShelfCount = 0
    var borrowCount = 0
    var reserveCount = 0
    var collectCount = 0
}

struct LibraryBorrowRecord: Decodable, Identifiable, Hashable {
    let callNo: String
    let location: String
    let status: String
    let realReturnTime: String?
    let returnTime: String?
    let createdTime: String
    let libraryDetail: DetailContainer

    var id: String { "\(callNo)|\(createdTime)|\(libraryDetail.detail.isbn)" }
    var statusText: String {
        switch status {
        case "0": "已还"
        case "2": "借阅中"
        case "02": "逾期待还"
        default: status
        }
    }

    struct DetailContainer: Decodable, Hashable { let detail: Detail }
    struct Detail: Decodable, Hashable {
        let isbn: String
        let title: String
        let authors: String
        let publishers: String
        let year: String
        let digest: String
        let keywords: String

        private enum CodingKeys: String, CodingKey {
            case isbn, title, authors, publishers, digest, keywords
            case year = "cbrq"
        }
    }
}

enum HuiXinFeeKind {
    case electricHefei(building: String, room: String)
    case electricXuancheng(room: String)
    case networkXuancheng
    case bathingHefei(phone: String)
    case bathingXuancheng(phone: String)

    var itemID: Int {
        switch self {
        case .electricHefei: 1
        case .electricXuancheng: 261
        case .networkXuancheng: 281
        case .bathingHefei: 222
        case .bathingXuancheng: 223
        }
    }

    var fields: [(String, String)] {
        var values = [("feeitemid", String(itemID)), ("type", "IEC")]
        switch self {
        case .electricHefei(let building, let room):
            values += [("level", "1"), ("campus", "1sh"), ("building", building), ("room", room)]
        case .electricXuancheng(let room):
            values += [("room", room)]
        case .networkXuancheng:
            values += [("level", "0")]
        case .bathingHefei(let phone):
            values += [("level", "1"), ("telPhone", phone)]
        case .bathingXuancheng(let phone):
            values += [("level", "1"), ("telPhone", phone)]
        }
        return values
    }
}

final class CampusServiceClient: @unchecked Sendable {
    static let shared = CampusServiceClient()

    private let session: URLSession
    private let noRedirectSession: URLSession
    private let huiXinTokenKey = "huixin-token"
    private let onePortalTokenKey = "one-portal-token"
    private let campusCardBalanceKey = "campus-card-balance"
    private let secondClassCookieKey = "second-class-cookie"
    private let libraryTokenKey = "library-token"
    private let showerPhoneKey = "shower-phone"
    private let showerCodeKey = "shower-login-code"

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = .shared
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 HFUTSchedule-iOS"
        ]
        session = URLSession(configuration: configuration)
        noRedirectSession = URLSession(
            configuration: configuration,
            delegate: CampusNoRedirectDelegate.shared,
            delegateQueue: nil
        )
    }

    var savedHuiXinToken: String? { CampusCredentialStore.read(huiXinTokenKey) }
    var hasSavedShowerCredentials: Bool {
        CampusCredentialStore.read(showerPhoneKey) != nil &&
        CampusCredentialStore.read(showerCodeKey) != nil
    }
    var cachedCampusCardBalance: Double? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: campusCardBalanceKey) != nil else { return nil }
        return defaults.double(forKey: campusCardBalanceKey)
    }
    var hasLibraryToken: Bool { CampusCredentialStore.read(libraryTokenKey) != nil }

    static let alipayCampusCardURL = URL(string: "alipays://platformapi/startapp?appId=20000067&url=https://ur.alipay.com/_4kQhV32216tp7bzlDc3E1k")!
    static let alipayCampusCardFallbackURL = URL(string: "https://ur.alipay.com/_4kQhV32216tp7bzlDc3E1k")!

    func fetchCampusMailURL(email: String, forceRefresh: Bool = false) async throws -> URL? {
        let token = try await onePortalToken(forceRefresh: forceRefresh)
        let secret = String((0..<16).compactMap { _ in "0123456789ABCDEF".randomElement() })
        let encrypted = try CASLoginClient.encryptAES(email, key: secret)
        var components = URLComponents(string: "https://one.hfut.edu.cn/api/msg/mailBusiness/getLoginUrl")!
        components.queryItems = [URLQueryItem(name: "mail", value: encrypted)]
        var request = URLRequest(url: components.url!)
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue("secret=\(secret)", forHTTPHeaderField: "Cookie")
        let (data, response) = try await self.data(for: request)
        if [401, 403].contains(response.statusCode), !forceRefresh {
            CampusCredentialStore.delete(onePortalTokenKey)
            return try await fetchCampusMailURL(email: email, forceRefresh: true)
        }
        guard (200..<300).contains(response.statusCode) else { throw CampusServiceError.http(response.statusCode) }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CampusServiceError.invalidData("校园邮箱接口返回格式无法识别")
        }
        // The official endpoint returns data = null when the student has not
        // activated a campus mailbox. That is a valid state, not a parse error.
        guard let value = Self.string(root["data"]), !value.isEmpty else { return nil }
        return URL(string: value)
    }

    /// 复用已保存的信息门户令牌，没有则登录一次。
    func ensureOnePortalToken() async throws -> String {
        try await onePortalToken(forceRefresh: false)
    }

    @discardableResult
    func refreshOnePortalToken() async throws -> String {
        CampusSessionStore.shared.restoreToSharedStorage()
        let redirect = "https://one.hfut.edu.cn/home/index"
        var components = URLComponents(string: "https://cas.hfut.edu.cn/cas/oauth2.0/authorize")!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: "BsHfutEduPortal"),
            URLQueryItem(name: "redirect_uri", value: redirect)
        ]
        guard let start = components.url else { throw CampusServiceError.invalidResponse }
        let callback = try await followRedirects(from: start) { url, headers, body in
            let candidates = [url.absoluteString, headers["location"] ?? "", body]
            return candidates.first { $0.contains("code=OC-") }
        }
        guard let callbackURL = URL(string: callback),
              let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value else {
            throw CampusServiceError.invalidData("信息门户未返回 OAuth code")
        }
        var exchange = URLComponents(string: "https://one.hfut.edu.cn/api/auth/oauth/getToken")!
        exchange.queryItems = [
            URLQueryItem(name: "type", value: "portal"),
            URLQueryItem(name: "redirect", value: callback),
            URLQueryItem(name: "code", value: code)
        ]
        let (data, response) = try await self.data(for: URLRequest(url: exchange.url!))
        guard (200..<300).contains(response.statusCode),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["data"] as? [String: Any],
              let rawToken = Self.string(payload["access_token"]), !rawToken.isEmpty else {
            throw CampusServiceError.authenticationRequired("信息门户")
        }
        let token = rawToken.lowercased().hasPrefix("bearer ") ? rawToken : "Bearer \(rawToken)"
        try CampusCredentialStore.write(token, account: onePortalTokenKey)
        return token
    }
    static let pinduoduoExpressURL = URL(string: "https://m.pinduoduo.net/mdkd/identificationCode")!
    static let taobaoExpressURL = URL(string: "https://pages-fast.m.taobao.com/wow/z/uniapp/1011717/last-mile-fe/end-collect-platform/identity-code")!

    func savedHuiXinPortalURL(path: String = "plat") -> URL? {
        guard let token = savedHuiXinToken else { return nil }
        var components = URLComponents(string: "http://121.251.19.62/\(path)")!
        components.queryItems = [URLQueryItem(name: "synjones-auth", value: token)]
        return components.url
    }

    func savedHuiXinChargeURL(itemID: Int) -> URL? {
        guard let token = savedHuiXinToken else { return nil }
        var components = URLComponents(string: "http://121.251.19.62/charge-app/")!
        components.queryItems = [
            URLQueryItem(name: "name", value: "pays"),
            URLQueryItem(name: "appsourse", value: "ydfwpt"),
            URLQueryItem(name: "id", value: String(itemID)),
            URLQueryItem(name: "paymentUrl", value: "http://121.251.19.62/plat"),
            URLQueryItem(name: "token", value: token)
        ]
        return components.url
    }

    @discardableResult
    func refreshLibraryToken() async throws -> String {
        CampusSessionStore.shared.restoreToSharedStorage()
        var components = URLComponents(string: "https://cas.hfut.edu.cn/cas/login")!
        components.queryItems = [
            URLQueryItem(
                name: "service",
                value: "https://lib.hfut.edu.cn/svc/sso/login/callback/portal/hfut"
            )
        ]
        guard let start = components.url else { throw CampusServiceError.invalidResponse }
        let token = try await followRedirects(from: start) { url, headers, _ in
            guard url.host?.lowercased() == "lib.hfut.edu.cn" else { return nil }
            let cookieText = headers["set-cookie"] ?? ""
            guard let raw = Self.firstMatch(
                in: cookieText,
                pattern: #"(?:^|[,;]\s*)Authorization=([^;,\s]+)"#
            ), raw.contains("ey") else { return nil }
            return raw.hasPrefix("Bearer ") ? raw : "Bearer \(raw)"
        }
        try CampusCredentialStore.write(token, account: libraryTokenKey)
        return token
    }

    func fetchLibraryStatus(retrying: Bool = false) async throws -> LibraryStatusSummary {
        let token = try await libraryToken(forceRefresh: retrying)
        var request = URLRequest(url: URL(string: "https://lib.hfut.edu.cn/svc/circulate/myLibCall/listMyLibStatis")!)
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        let (data, response) = try await self.data(for: request)
        if [401, 403].contains(response.statusCode), !retrying {
            CampusCredentialStore.delete(libraryTokenKey)
            return try await fetchLibraryStatus(retrying: true)
        }
        guard (200..<300).contains(response.statusCode) else { throw CampusServiceError.http(response.statusCode) }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["data"] as? [[String: Any]] else {
            if !retrying {
                CampusCredentialStore.delete(libraryTokenKey)
                return try await fetchLibraryStatus(retrying: true)
            }
            throw CampusServiceError.invalidData("图书馆未返回借阅统计")
        }
        var result = LibraryStatusSummary()
        for row in rows {
            let count = Int(Self.string(row["count"]) ?? "0") ?? 0
            switch Self.string(row["code"]) {
            case "mybookshelf": result.bookShelfCount = count
            case "myborrow": result.borrowCount = count
            case "myreserve": result.reserveCount = count
            case "mycollect": result.collectCount = count
            default: break
            }
        }
        return result
    }

    func fetchLibraryBorrowRecords(page: Int = 1, pageSize: Int = 30, retrying: Bool = false) async throws -> [LibraryBorrowRecord] {
        let token = try await libraryToken(forceRefresh: retrying)
        var components = URLComponents(string: "https://lib.hfut.edu.cn/svc/circulate/readerRecord")!
        components.queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "limit", value: String(max(pageSize, 30)))
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(token, forHTTPHeaderField: "Authorization")
        let (data, response) = try await self.data(for: request)
        if [401, 403].contains(response.statusCode), !retrying {
            CampusCredentialStore.delete(libraryTokenKey)
            return try await fetchLibraryBorrowRecords(page: page, pageSize: pageSize, retrying: true)
        }
        guard (200..<300).contains(response.statusCode) else { throw CampusServiceError.http(response.statusCode) }
        do {
            return try JSONDecoder().decode(LibraryBorrowEnvelope.self, from: data).data.list
        } catch {
            if !retrying {
                CampusCredentialStore.delete(libraryTokenKey)
                return try await fetchLibraryBorrowRecords(page: page, pageSize: pageSize, retrying: true)
            }
            throw CampusServiceError.invalidData("图书馆借阅记录解析失败：\(error.localizedDescription)")
        }
    }

    @discardableResult
    func refreshHuiXinToken() async throws -> String {
        CampusSessionStore.shared.restoreToSharedStorage()
        let redirect = "http://121.251.19.62/berserker-auth/cas/oauth2url?oauth2url=http://121.251.19.62/berserker-base/redirect"
        var components = URLComponents(string: "https://cas.hfut.edu.cn/cas/oauth2.0/authorize")!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: "Hfut2023Ydfwpt"),
            URLQueryItem(name: "redirect_uri", value: redirect)
        ]
        guard let start = components.url else { throw CampusServiceError.invalidResponse }
        var lastError: Error?
        for _ in 0..<2 {
            do {
                let token = try await followRedirects(from: start) { url, headers, body in
                    let candidates = [url.absoluteString, headers["location"] ?? "", body]
                    for candidate in candidates {
                        if let value = Self.firstMatch(in: candidate, pattern: #"synjones-auth=([^&\s\"']+)"#) {
                            return value.removingPercentEncoding ?? value
                        }
                    }
                    return nil
                }
                try CampusCredentialStore.write(token, account: huiXinTokenKey)
                return token
            } catch {
                lastError = error
            }
        }
        throw lastError ?? CampusServiceError.authenticationRequired("一卡通")
    }

    func fetchCampusCards(forceRefresh: Bool = false) async throws -> [HuiXinCard] {
        let token = try await huiXinToken(forceRefresh: forceRefresh)
        var components = URLComponents(string: "http://121.251.19.62/berserker-app/ykt/tsm/getCampusCards")!
        components.queryItems = [URLQueryItem(name: "synAccessSource", value: "h5")]
        var request = URLRequest(url: components.url!)
        request.setValue(token, forHTTPHeaderField: "synjones-auth")
        let (data, response) = try await data(for: request)
        if [401, 403].contains(response.statusCode), !forceRefresh {
            CampusCredentialStore.delete(huiXinTokenKey)
            return try await fetchCampusCards(forceRefresh: true)
        }
        guard (200..<300).contains(response.statusCode) else { throw CampusServiceError.http(response.statusCode) }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CampusServiceError.invalidData("一卡通接口返回格式无法识别")
        }
        if Self.isAuthenticationFailure(root), !forceRefresh {
            CampusCredentialStore.delete(huiXinTokenKey)
            return try await fetchCampusCards(forceRefresh: true)
        }
        guard
              let dataObject = root["data"] as? [String: Any],
              let cards = dataObject["card"] as? [[String: Any]] else {
            let message = Self.string(root["msg"]) ?? Self.string(root["message"]) ?? "一卡通接口未返回卡片信息"
            throw CampusServiceError.invalidData(message)
        }
        let parsedCards: [HuiXinCard] = cards.compactMap { card -> HuiXinCard? in
            guard let account = Self.string(card["account"]) else { return nil }
            return HuiXinCard(
                account: account,
                name: Self.string(card["name"]) ?? "校园卡",
                balance: Self.money(card["db_balance"]),
                unsettledAmount: Self.money(card["unsettle_amount"]),
                autoTransferLimit: Self.money(card["autotrans_limite"]),
                autoTransferAmount: Self.money(card["autotrans_amt"])
            )
        }
        if let card = parsedCards.first {
            // Android's focus card shows the available balance plus unsettled
            // transactions, then persists that display value for offline use.
            UserDefaults.standard.set(
                card.balance + card.unsettledAmount,
                forKey: campusCardBalanceKey
            )
        }
        return parsedCards
    }

    func fetchFee(_ kind: HuiXinFeeKind, retrying: Bool = false) async throws -> [String: String] {
        let token = try await huiXinToken(forceRefresh: retrying)
        var request = URLRequest(url: URL(string: "http://121.251.19.62/charge/feeitem/getThirdData")!)
        request.httpMethod = "POST"
        request.setValue("bearer \(token)", forHTTPHeaderField: "synjones-auth")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(kind.fields)
        let (data, response) = try await data(for: request)
        if [401, 403].contains(response.statusCode), !retrying {
            CampusCredentialStore.delete(huiXinTokenKey)
            return try await fetchFee(kind, retrying: true)
        }
        guard (200..<300).contains(response.statusCode) else { throw CampusServiceError.http(response.statusCode) }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CampusServiceError.invalidData("费用接口返回格式无法识别")
        }
        if Self.isAuthenticationFailure(root), !retrying {
            CampusCredentialStore.delete(huiXinTokenKey)
            return try await fetchFee(kind, retrying: true)
        }
        let map = root["map"] as? [String: Any]
        let showData = (map?["showData"] as? [String: Any])
            ?? ((root["data"] as? [String: Any])?["showData"] as? [String: Any])
        guard let showData else {
            let message = Self.string(root["msg"]) ?? Self.string(root["message"]) ?? "未查询到费用信息"
            throw CampusServiceError.invalidData(message)
        }
        return showData.reduce(into: [String: String]()) { result, pair in
            result[pair.key] = Self.string(pair.value) ?? String(describing: pair.value)
        }
    }

    func fetchHefeiElectricOptions(building: String? = nil, retrying: Bool = false) async throws -> [HuiXinSelectionOption] {
        let token = try await huiXinToken(forceRefresh: retrying)
        var fields = [
            ("feeitemid", "1"), ("type", "select"), ("campus", "1sh"),
            ("level", building == nil ? "1" : "2")
        ]
        if let building { fields.append(("building", building)) }
        var request = URLRequest(url: URL(string: "http://121.251.19.62/charge/feeitem/getThirdData")!)
        request.httpMethod = "POST"
        request.setValue("bearer \(token)", forHTTPHeaderField: "synjones-auth")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(fields)
        let (data, response) = try await data(for: request)
        if [401, 403].contains(response.statusCode), !retrying {
            CampusCredentialStore.delete(huiXinTokenKey)
            return try await fetchHefeiElectricOptions(building: building, retrying: true)
        }
        guard (200..<300).contains(response.statusCode) else { throw CampusServiceError.http(response.statusCode) }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let map = root["map"] as? [String: Any],
              let values = map["data"] as? [[String: Any]] else {
            throw CampusServiceError.invalidData("电费接口未返回楼栋或房间列表")
        }
        return values.compactMap { value in
            guard let name = Self.string(value["name"]), let code = Self.string(value["value"]) else { return nil }
            return HuiXinSelectionOption(name: name, value: code)
        }
    }

    func huiXinPortalURL(path: String = "plat") async throws -> URL {
        let token = try await huiXinToken(forceRefresh: false)
        var components = URLComponents(string: "http://121.251.19.62/\(path)")!
        components.queryItems = [URLQueryItem(name: "synjones-auth", value: token)]
        guard let url = components.url else { throw CampusServiceError.invalidResponse }
        return url
    }

    func huiXinChargeURL(itemID: Int) async throws -> URL {
        let token = try await huiXinToken(forceRefresh: false)
        var components = URLComponents(string: "http://121.251.19.62/charge-app/")!
        components.queryItems = [
            URLQueryItem(name: "name", value: "pays"),
            URLQueryItem(name: "appsourse", value: "ydfwpt"),
            URLQueryItem(name: "id", value: String(itemID)),
            URLQueryItem(name: "paymentUrl", value: "http://121.251.19.62/plat"),
            URLQueryItem(name: "token", value: token)
        ]
        guard let url = components.url else { throw CampusServiceError.invalidResponse }
        return url
    }

    func fetchSecondClassActivities(page: Int = 1, retrying: Bool = false) async throws -> [SecondClassActivity] {
        let cookie = try await secondClassCookie(forceRefresh: retrying)
        var components = URLComponents(string: "https://dekt.hfut.edu.cn/scReports/activity/activityPage")!
        components.queryItems = [
            URLQueryItem(name: "pageNo", value: String(page)),
            URLQueryItem(name: "pageSize", value: "30")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        let (data, response) = try await data(for: request)
        let text = String(data: data, encoding: .utf8) ?? ""
        if response.statusCode == 401 || response.statusCode == 403 || text.contains("<!DOCTYPE html") {
            if retrying { throw CampusServiceError.authenticationRequired("第二课堂") }
            CampusCredentialStore.delete(secondClassCookieKey)
            return try await fetchSecondClassActivities(page: page, retrying: true)
        }
        guard (200..<300).contains(response.statusCode) else { throw CampusServiceError.http(response.statusCode) }
        return try JSONDecoder().decode(SecondClassEnvelope.self, from: data).list
    }

    func loginShower(phone: String, password: String) async throws -> ShowerProfile {
        let digest = Insecure.MD5.hash(data: Data(password.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let encrypted = String(digest.suffix(10)).uppercased()
        var request = URLRequest(url: URL(string: "https://bathing.hfut.edu.cn/user/login")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody([
            ("telPhone", phone), ("password", encrypted), ("typeId", "0")
        ])
        let (data, response) = try await data(for: request)
        guard (200..<300).contains(response.statusCode) else { throw CampusServiceError.http(response.statusCode) }
        let profile = try Self.parseShowerProfile(data)
        try CampusCredentialStore.write(profile.phone, account: showerPhoneKey)
        try CampusCredentialStore.write(profile.loginCode, account: showerCodeKey)
        return profile
    }

    func fetchShowerProfile() async throws -> ShowerProfile {
        guard let phone = CampusCredentialStore.read(showerPhoneKey),
              let code = CampusCredentialStore.read(showerCodeKey) else {
            throw CampusServiceError.authenticationRequired("呱呱物联")
        }
        var components = URLComponents(string: "https://bathing.hfut.edu.cn/user/info")!
        components.queryItems = [
            URLQueryItem(name: "telPhone", value: phone),
            URLQueryItem(name: "loginCode", value: code)
        ]
        let (data, response) = try await data(for: URLRequest(url: components.url!))
        guard (200..<300).contains(response.statusCode) else { throw CampusServiceError.http(response.statusCode) }
        return try Self.parseShowerProfile(data, fallbackPhone: phone, fallbackCode: code)
    }

    func fetchLaundryLocations(xuancheng: Bool, categoryCode: String? = nil, page: Int = 1) async throws -> [LaundryLocation] {
        let coordinate = xuancheng ? (118.710182, 30.903593) : (117.20346, 31.77014)
        var json: [String: Any] = [
            "lng": coordinate.0,
            "lat": coordinate.1,
            "page": page,
            "pageSize": 30
        ]
        if let categoryCode { json["categoryCode"] = categoryCode }
        var request = URLRequest(url: URL(string: "https://yshz-user.haier-ioc.com/position/nearPosition")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: json)
        let (data, response) = try await data(for: request)
        guard (200..<300).contains(response.statusCode) else { throw CampusServiceError.http(response.statusCode) }
        return try JSONDecoder().decode(LaundryEnvelope.self, from: data).data.items.filter { location in
            if xuancheng { return location.address.contains("宣州区薰化路301号") }
            return location.address.contains("合肥工业大学") || location.name.contains("屯溪路") || location.name.contains("翡翠湖")
        }
    }

    func fetchLaundryDevices(positionID: Int64, categoryCode: String, page: Int = 1) async throws -> [LaundryDevice] {
        var request = URLRequest(url: URL(string: "https://yshz-user.haier-ioc.com/position/deviceDetailPage")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "positionId": String(positionID),
            "categoryCode": categoryCode,
            "page": page,
            "pageSize": 30
        ])
        let (data, response) = try await data(for: request)
        guard (200..<300).contains(response.statusCode) else { throw CampusServiceError.http(response.statusCode) }
        return try JSONDecoder().decode(LaundryDeviceEnvelope.self, from: data).data.items
    }

    private func huiXinToken(forceRefresh: Bool) async throws -> String {
        if !forceRefresh, let token = CampusCredentialStore.read(huiXinTokenKey), !token.isEmpty { return token }
        return try await refreshHuiXinToken()
    }

    private func onePortalToken(forceRefresh: Bool) async throws -> String {
        if !forceRefresh,
           let token = CampusCredentialStore.read(onePortalTokenKey),
           !token.isEmpty { return token }
        return try await refreshOnePortalToken()
    }

    private func libraryToken(forceRefresh: Bool) async throws -> String {
        if !forceRefresh, let token = CampusCredentialStore.read(libraryTokenKey), !token.isEmpty { return token }
        return try await refreshLibraryToken()
    }

    private func secondClassCookie(forceRefresh: Bool) async throws -> String {
        if !forceRefresh, let cookie = CampusCredentialStore.read(secondClassCookieKey), !cookie.isEmpty { return cookie }
        CampusSessionStore.shared.restoreToSharedStorage()
        var components = URLComponents(string: "https://cas.hfut.edu.cn/cas/login")!
        components.queryItems = [URLQueryItem(name: "service", value: "https://dekt.hfut.edu.cn/scReports/uccp_index")]
        guard let start = components.url else { throw CampusServiceError.invalidResponse }
        let cookie = try await followRedirects(from: start) { url, headers, _ in
            let setCookie = headers["set-cookie"] ?? ""
            if url.host == "dekt.hfut.edu.cn",
               let token = Self.firstMatch(in: setCookie, pattern: #"(?:^|[,;]\s*)(SESSION=[^;,\s]+)"#) {
                return token
            }
            if url.host == "dekt.hfut.edu.cn",
               let value = HTTPCookieStorage.shared.cookies(for: URL(string: "https://dekt.hfut.edu.cn/")!)?.first(where: { $0.name == "SESSION" })?.value {
                return "SESSION=\(value)"
            }
            return nil
        }
        try CampusCredentialStore.write(cookie, account: secondClassCookieKey)
        return cookie
    }

    private func followRedirects(
        from start: URL,
        extractor: (URL, [String: String], String) -> String?
    ) async throws -> String {
        var current = start
        for _ in 0..<12 {
            var request = URLRequest(url: current)
            let requestCookies = HTTPCookieStorage.shared.cookies(for: current) ?? []
            if !requestCookies.isEmpty {
                request.setValue(
                    requestCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; "),
                    forHTTPHeaderField: "Cookie"
                )
            }
            let (data, response) = try await noRedirectSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw CampusServiceError.invalidResponse }
            let responseHeaders = http.allHeaderFields.reduce(into: [String: String]()) { result, item in
                guard let key = item.key as? String else { return }
                result[key] = String(describing: item.value)
            }
            let responseCookies = HTTPCookie.cookies(
                withResponseHeaderFields: responseHeaders,
                for: http.url ?? current
            )
            for cookie in responseCookies { HTTPCookieStorage.shared.setCookie(cookie) }
            CampusSessionStore.shared.persist((HTTPCookieStorage.shared.cookies ?? []) + responseCookies)
            let headers = http.allHeaderFields.reduce(into: [String: String]()) { result, item in
                guard let key = item.key as? String else { return }
                result[key.lowercased()] = String(describing: item.value)
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            if let value = extractor(http.url ?? current, headers, body) { return value }
            guard (300..<400).contains(http.statusCode),
                  let location = http.value(forHTTPHeaderField: "Location"),
                  let next = URL(string: location, relativeTo: http.url ?? current)?.absoluteURL else {
                throw CampusServiceError.authenticationRequired("统一身份认证")
            }
            current = next
        }
        throw CampusServiceError.invalidResponse
    }

    private func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        CampusSessionStore.shared.restoreToSharedStorage()
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw CampusServiceError.invalidResponse }
        CampusSessionStore.shared.persist(HTTPCookieStorage.shared.cookies ?? [])
        return (data, response)
    }

    private static func formBody(_ values: [(String, String)]) -> Data {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return values.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&").data(using: .utf8)!
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private static func string(_ value: Any?) -> String? {
        switch value {
        case let value as String: value
        case let value as NSNumber: value.stringValue
        default: nil
        }
    }

    private static func money(_ value: Any?) -> Double {
        let raw: Double
        switch value {
        case let number as NSNumber: raw = number.doubleValue
        case let text as String: raw = Double(text) ?? 0
        default: raw = 0
        }
        return raw / 100
    }

    private static func isAuthenticationFailure(_ root: [String: Any]) -> Bool {
        let message = [string(root["msg"]), string(root["message"]), string(root["error"])]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        return message.contains("登录")
            || message.contains("令牌")
            || message.contains("token")
            || message.contains("unauthorized")
    }

    private static func parseShowerProfile(
        _ data: Data,
        fallbackPhone: String? = nil,
        fallbackCode: String? = nil
    ) throws -> ShowerProfile {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let object = root["data"] as? [String: Any] else {
            let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw CampusServiceError.invalidData(string(root?["message"]) ?? "洗浴平台未返回用户信息")
        }
        let phone = string(object["telPhone"]) ?? fallbackPhone ?? ""
        let code = string(object["loginCode"]) ?? fallbackCode ?? ""
        guard !phone.isEmpty, !code.isEmpty else {
            throw CampusServiceError.invalidData(string(root["message"]) ?? "洗浴平台登录失败")
        }
        return ShowerProfile(
            phone: phone,
            name: string(object["name"]) ?? "洗浴账户",
            balance: money(object["accountMoney"]),
            giftedBalance: money(object["accountGivenMoney"]),
            loginCode: code
        )
    }
}

enum CampusServiceError: LocalizedError {
    case invalidResponse
    case invalidData(String)
    case http(Int)
    case authenticationRequired(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "校方服务返回了无法识别的响应。"
        case .invalidData(let message): message
        case .http(let status): "校方服务请求失败（HTTP \(status)）。"
        case .authenticationRequired(let service): "\(service)登录状态已失效，请先在“选项 → 安全登录”完成一次统一身份认证。"
        }
    }
}

private struct SecondClassEnvelope: Decodable { let list: [SecondClassActivity] }
private struct LibraryBorrowEnvelope: Decodable {
    let data: DataValue
    struct DataValue: Decodable { let list: [LibraryBorrowRecord] }
}
private struct LaundryEnvelope: Decodable {
    let data: DataValue
    struct DataValue: Decodable { let items: [LaundryLocation] }
}
private struct LaundryDeviceEnvelope: Decodable {
    let data: DataValue
    struct DataValue: Decodable { let items: [LaundryDevice] }
}

private enum CampusCredentialStore {
    private static let service = "com.xiaozhangwangxue.hfutschedule.campus-credentials"

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
        guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else {
            throw CampusServiceError.invalidData("无法安全保存校方登录令牌")
        }
    }

    static func delete(_ account: String) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ] as CFDictionary)
    }
}

private final class CampusNoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = CampusNoRedirectDelegate()
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
