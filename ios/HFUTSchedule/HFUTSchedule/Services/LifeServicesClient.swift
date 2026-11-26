import Foundation
import CoreFoundation
import CryptoKit

enum LifeCredentialPolicy {
    static func cardCredentials(defaults: UserDefaults = .standard) throws -> (username: String, password: String) {
        let info = student(defaults)
        guard let account = info?.studentID, !account.isEmpty else { throw CampusServiceError.invalidData("请先同步学籍中的学号") }
        let useDefault = defaults.object(forKey: AppSettingsKey.useDefaultCardPassword) == nil || defaults.bool(forKey: AppSettingsKey.useDefaultCardPassword)
        let password = useDefault ? AppSecretStore.defaultPassword(fromIdentity: info?.fields["身份证号"] ?? info?.fields["证件号"]) : AppSecretStore.read(AppSecretStore.Account.cardPassword)
        guard let password, password.count == 6 else { throw CampusServiceError.invalidData("请在偏好设置中录入正确的一卡通密码，或同步默认密码所需的证件信息") }
        return (account, password)
    }
    static func networkCredentials(xuancheng: Bool, defaults: UserDefaults = .standard) throws -> (username: String, password: String) {
        if xuancheng { return try cardCredentials(defaults: defaults) }
        let info = student(defaults)
        guard let account = info?.studentID, !account.isEmpty else { throw CampusServiceError.invalidData("请先同步学籍中的学号") }
        let useDefault = defaults.object(forKey: "useDefaultSchoolNetPassword") == nil || defaults.bool(forKey: "useDefaultSchoolNetPassword")
        let identity = info?.fields["身份证号"] ?? info?.fields["证件号"]
        // Upstream's Hefei network password retains a trailing X; its card
        // password deliberately uses the six digits before X instead.
        let password = useDefault ? identity.map { String($0.suffix(6)) } : AppSecretStore.read(AppSecretStore.Account.schoolNetPassword)
        guard let password, password.count == 6 else { throw CampusServiceError.invalidData("请在偏好设置中录入正确的校园网密码") }
        return (account, password)
    }
    private static func student(_ defaults: UserDefaults) -> AcademicStudentInfo? {
        defaults.data(forKey: "academicStudentInfo").flatMap { try? JSONDecoder().decode(AcademicStudentInfo.self, from: $0) }
    }
}

struct CampusCardBillPage: Decodable {
    let records: [CampusCardBill]
    let total: Int
    let size: Int
    init(records: [CampusCardBill], total: Int, size: Int) { self.records = records; self.total = total; self.size = size }
    private enum CodingKeys: String, CodingKey { case records, total, size }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        records = try c.decode([CampusCardBill].self, forKey: .records)
        total = try c.billInteger(.total) ?? records.count
        size = try c.billInteger(.size) ?? records.count
    }
}
struct CampusCardBill: Decodable, Identifiable, Hashable {
    var id: String { "\(orderId)|\(jndatetimeStr)|\(resume)|\(tranamt ?? 0)" }
    let tranamt: Int?
    let resume: String
    let fromAccount: String
    let turnoverType: String
    let orderId: String
    let jndatetimeStr: String
    let effectdateStr: String
    init(tranamt: Int?, resume: String, fromAccount: String, turnoverType: String, orderId: String, jndatetimeStr: String, effectdateStr: String) {
        self.tranamt = tranamt; self.resume = resume; self.fromAccount = fromAccount; self.turnoverType = turnoverType
        self.orderId = orderId; self.jndatetimeStr = jndatetimeStr; self.effectdateStr = effectdateStr
    }
    private enum CodingKeys: String, CodingKey { case tranamt, resume, fromAccount, turnoverType, orderId, jndatetimeStr, effectdateStr }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tranamt = try c.billInteger(.tranamt)
        resume = c.billString(.resume); fromAccount = c.billString(.fromAccount)
        turnoverType = c.billString(.turnoverType); orderId = c.billString(.orderId)
        jndatetimeStr = c.billString(.jndatetimeStr); effectdateStr = c.billString(.effectdateStr)
    }
    var amount: Double { Double(tranamt ?? 0) / 100 }
    var day: String { String(jndatetimeStr.prefix(10)) }
}
private extension KeyedDecodingContainer {
    func billString(_ key: Key) -> String {
        (try? decode(String.self, forKey: key)) ?? (try? decode(Int64.self, forKey: key)).map(String.init) ?? ""
    }
    func billInteger(_ key: Key) throws -> Int? {
        if !contains(key) { return nil }
        if try decodeNil(forKey: key) { return nil }
        if let value = try? decode(Int.self, forKey: key) { return value }
        if let value = try? decode(String.self, forKey: key), let number = Double(value), number.isFinite, number.rounded() == number,
           let result = Int(exactly: number) { return result }
        throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "金额或分页数量不是整数")
    }
}

/// Walk actual pages: HuiXin may cap the requested page size. Never silently
/// turn the first capped page into a complete consumption analysis.
enum CampusCardPagination {
    static func all(fetch: (Int, Int) async throws -> CampusCardBillPage) async throws -> [CampusCardBill] {
        var page = 1, results: [CampusCardBill] = [], seen = Set<String>()
        while true {
            try Task.checkCancellation()
            let response = try await fetch(page, 100)
            let additions = response.records.filter { seen.insert($0.id).inserted }
            results.append(contentsOf: additions)
            if results.count >= response.total { return results }
            guard !additions.isEmpty, page < 10000 else {
                throw CampusServiceError.invalidData("账单分页未完整返回，请稍后重新加载分析")
            }
            page += 1
        }
    }
}

struct CampusCardRangeTotal: Decodable { let income: Double; let expenses: Double }
struct CampusCardForecast: Equatable {
    let dailyAmounts: [String: Double]
    let monthlyAmounts: [String: Double]
    let merchants: [String: Double]
    let dailyAverage: Double
    let monthlyAverage: Double
    let nextDay: Double?
    let nextMonth: Double?
    let dailyR2: Double?
    let monthlyR2: Double?
}
enum CampusCardAnalysis {
    static func forecast(_ bills: [CampusCardBill]) -> CampusCardForecast {
        let washed = bills.filter { $0.turnoverType == "消费" && !$0.resume.contains("电") }
        let daily = Dictionary(grouping: washed, by: \.day).mapValues { $0.reduce(0) { $0 + $1.amount } }
        let monthly = Dictionary(grouping: daily.keys, by: { String($0.prefix(7)) }).mapValues { $0.reduce(0) { $0 + (daily[$1] ?? 0) } }
        let merchants = Dictionary(grouping: bills.filter { $0.turnoverType == "消费" }, by: \.resume).mapValues { $0.reduce(0) { $0 + $1.amount } }
        let dates = daily.keys.sorted()
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        let origin = dates.first.flatMap { formatter.date(from: $0) }
        let days: [(Double, Double)] = dates.compactMap { key in
            guard let origin, let date = formatter.date(from: key), let value = daily[key] else { return nil }
            return (Double(Calendar.current.dateComponents([.day], from: origin, to: date).day ?? 0), value)
        }
        let months = monthly.keys.sorted().enumerated().map { (Double($0.offset), monthly[$0.element] ?? 0) }
        let day = linearForecast(days), month = linearForecast(months)
        return CampusCardForecast(dailyAmounts: daily, monthlyAmounts: monthly, merchants: merchants,
            dailyAverage: daily.isEmpty ? 0 : daily.values.reduce(0, +) / Double(daily.count),
            monthlyAverage: monthly.isEmpty ? 0 : monthly.values.reduce(0, +) / Double(monthly.count),
            nextDay: day?.0, nextMonth: month?.0, dailyR2: day?.1, monthlyR2: month?.1)
    }
    /// Mirrors upstream's two-standard-deviation filter and least-squares fit.
    /// A single observation has no defined slope, so it is shown as insufficient data.
    static func linearForecast(_ points: [(Double, Double)]) -> (Double, Double)? {
        guard points.count >= 2 else { return nil }
        let mean = points.map(\.1).reduce(0, +) / Double(points.count)
        let deviation = sqrt(points.reduce(0) { $0 + pow($1.1 - mean, 2) } / Double(points.count))
        let filtered = points.filter { abs($0.1 - mean) <= 2 * deviation }
        let n = Double(filtered.count), sx = filtered.map(\.0).reduce(0, +), sy = filtered.map(\.1).reduce(0, +)
        let sxy = filtered.reduce(0) { $0 + $1.0 * $1.1 }, sx2 = filtered.reduce(0) { $0 + $1.0 * $1.0 }
        let denominator = n * sx2 - sx * sx
        guard filtered.count >= 2, abs(denominator) > .ulpOfOne else { return nil }
        let a = (n * sxy - sx * sy) / denominator, b = (sy - a * sx) / n
        let forecast = a * ((filtered.map(\.0).max() ?? 0) + 1) + b
        let average = sy / n
        let residual = filtered.reduce(0) { $0 + pow($1.1 - (a * $1.0 + b), 2) }
        let total = filtered.reduce(0) { $0 + pow($1.1 - average, 2) }
        let r2 = total == 0 ? 1 : 1 - residual / total
        return forecast.isFinite && r2.isFinite ? (forecast, r2) : nil
    }
}

extension CampusServiceClient {
    func fetchCampusCardBills(page: Int = 1, size: Int = 30, keyword: String = "") async throws -> CampusCardBillPage {
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "current", value: "\(page)"), URLQueryItem(name: "size", value: "\(size)")]
        if !keyword.isEmpty { components.queryItems?.append(URLQueryItem(name: "info", value: keyword)) }
        let data = try await huiXinAuthorizedData(path: "berserker-search/search/personal/turnover\(components.string ?? "")")
        struct Envelope: Decodable { let data: CampusCardBillPage }
        return try JSONDecoder().decode(Envelope.self, from: data).data
    }
    func fetchAllCampusCardBills() async throws -> [CampusCardBill] {
        try await CampusCardPagination.all { page, size in
            try await fetchCampusCardBills(page: page, size: size)
        }
    }
    func fetchCampusCardMonthlyAmounts(month: String) async throws -> [String: Double] {
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "dateType", value: "month"), URLQueryItem(name: "statisticsDateStr", value: "day"), URLQueryItem(name: "type", value: "2"), URLQueryItem(name: "dateStr", value: month)]
        let data = try await huiXinAuthorizedData(path: "berserker-search/statistics/turnover/sum/user\(components.string ?? "")")
        struct Envelope: Decodable { let data: [String: Double] }
        return try JSONDecoder().decode(Envelope.self, from: data).data.mapValues { $0 / 100 }
    }
    func fetchCampusCardRange(from: String, to: String) async throws -> CampusCardRangeTotal {
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "timeFrom", value: from), URLQueryItem(name: "timeTo", value: to)]
        let data = try await huiXinAuthorizedData(path: "berserker-search/statistics/turnover/count\(components.string ?? "")")
        struct Envelope: Decodable { let data: CampusCardRangeTotal }
        let value = try JSONDecoder().decode(Envelope.self, from: data).data
        return CampusCardRangeTotal(income: value.income / 100, expenses: value.expenses / 100)
    }
}

struct ShowerBill: Decodable, Identifiable {
    var id: String { "\(dealDate)|\(dealMark)|\(description)|\(xfMoney ?? dealMoney ?? 0)" }
    let dealDate: String
    let dealMark: String
    let description: String
    let xfMoney: Double?
    let dealMoney: Double?
}
enum ShowerDeviceCode {
    static func normalized(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "").uppercased()
        guard value.utf8.count == 12, value.unicodeScalars.allSatisfy({ (48...57).contains($0.value) || (65...70).contains($0.value) }) else { return nil }
        return value
    }
    static func fromQRCode(_ text: String) -> String? {
        guard text.contains("KLCXKJ-Water") else { return nil }
        let fields = text.components(separatedBy: ",")
        guard fields.count >= 3 else { return nil }
        return normalized(fields[2])
    }
}
extension CampusServiceClient {
    func showerUseCode() async throws -> String {
        let data = try await showerAuthorizedData(path: "user/useCode")
        struct Envelope: Decodable { let data: Code; struct Code: Decodable { let randomCode: String } }
        return try JSONDecoder().decode(Envelope.self, from: data).data.randomCode
    }
    func resetShowerUseCode(password: String, securityCode: String) async throws -> AcademicSubmissionResult {
        guard securityCode.count == 5, securityCode.allSatisfy(\.isNumber) else { throw CampusServiceError.invalidData("新的使用码必须是5位数字") }
        let data = try await showerAuthorizedData(path: "user/useCode/set", method: "POST", fields: [("password", Self.showerPasswordHash(password)), ("securityCode", securityCode), ("appId", "10010")])
        return try Self.showerSubmission(data)
    }
    func startShower(deviceCode: String) async throws -> AcademicSubmissionResult {
        guard let code = ShowerDeviceCode.normalized(deviceCode) else { throw CampusServiceError.invalidData("花洒MAC地址必须为12位十六进制字符") }
        let data = try await showerAuthorizedData(path: "order/downRate/snWater", method: "POST", fields: [("deviceSncode", code), ("appId", "10010")])
        return try Self.showerSubmission(data)
    }
    func showerBills(page: Int = 1, from: String = "2023-10-01 00:00:00", to: String = "2050/12/31 23:59:59") async throws -> [ShowerBill] {
        let data = try await showerAuthorizedData(path: "wallet/billList", fields: [("curNum", "\(page)"), ("typeId", "0"), ("beginDate", from), ("endDate", to)])
        struct Envelope: Decodable { let data: [ShowerBill] }
        return try JSONDecoder().decode(Envelope.self, from: data).data
    }
    static func showerPasswordHash(_ password: String) -> String { String(Insecure.MD5.hash(data: Data(password.utf8)).map { String(format: "%02x", $0) }.joined().suffix(10)).uppercased() }
    private static func showerSubmission(_ data: Data) throws -> AcademicSubmissionResult {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let message = root["message"] as? String else { throw CampusServiceError.invalidData("洗浴平台返回格式无法识别") }
        return AcademicSubmissionResult(success: message.contains("成功"), message: message)
    }
}

struct SchoolNetworkStatus: Codable, Equatable {
    let gateway: String
    let fee: Double
    let usedMB: Double
    let updatedAt: Date
}
struct SchoolNetworkMonthRecord: Identifiable, Hashable {
    var id: String { "\(startDate)|\(endDate)|\(packageName)|\(billTime)" }
    let startDate: String
    let endDate: String
    let packageName: String
    let baseFee: Double
    let usageFee: Double
    let durationMinutes: Int
    let flowMB: Double
    let billTime: String
}

actor SchoolNetworkClient {
    static let shared = SchoolNetworkClient()
    private let session: URLSession
    private let selfBase = URL(string: "https://xywzz.hfut.edu.cn:8443/")!
    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = .shared
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 40
        session = URLSession(configuration: configuration)
    }
    static func gateways(xuancheng: Bool) -> [URL] { (xuancheng ? ["http://172.18.3.3/", "http://172.18.2.2/"] : ["http://172.16.200.11/"]).compactMap(URL.init(string:)) }
    func login(xuancheng: Bool) async throws -> String {
        let credentials = try LifeCredentialPolicy.networkCredentials(xuancheng: xuancheng)
        let results = await CampusNetworkLoginClient().login(region: xuancheng ? .xuancheng : .hefei, username: credentials.username, password: credentials.password, session: session)
        return results.map { "\($0.server)：\($0.message)" }.joined(separator: "\n")
    }
    func logout(xuancheng: Bool) async throws -> String {
        var messages: [String] = []
        for gateway in Self.gateways(xuancheng: xuancheng) {
            do { let html = try await request(URL(string: "F.htm", relativeTo: gateway)!); messages.append("\(gateway.host ?? "")：\(String(AcademicHTMLElement.parse(html).normalizedText.prefix(160)))") }
            catch { messages.append("\(gateway.host ?? "")：\(error.localizedDescription)") }
        }
        return messages.joined(separator: "\n")
    }
    func status(xuancheng: Bool) async throws -> SchoolNetworkStatus {
        var lastError: Error = CampusServiceError.invalidData("校园网网关未响应")
        for gateway in Self.gateways(xuancheng: xuancheng) {
            do {
                let html = try await request(URL(string: "a31.htm", relativeTo: gateway)!)
                let status = try Self.parseStatus(html, gateway: gateway.host ?? "")
                if let data = try? JSONEncoder().encode(status) { UserDefaults.standard.set(data, forKey: "nativeSchoolNetworkStatus") }
                return status
            } catch { lastError = error }
        }
        throw lastError
    }
    static func parseStatus(_ html: String, gateway: String) throws -> SchoolNetworkStatus {
        let flowText = AcademicHTMLText.matches(html, "\\bflow\\s*=\\s*['\"]?([0-9.]+)").first?[1]
        let feeText = AcademicHTMLText.matches(html, "\\bfee\\s*=\\s*['\"]?(-?[0-9.]+)").first?[1]
        guard let flowText, let flow = Double(flowText), let feeText, let fee = Double(feeText), flow.isFinite, fee.isFinite else { throw CampusServiceError.invalidData("网关未返回已登录状态；请连接校园Wi-Fi并登录") }
        return SchoolNetworkStatus(gateway: gateway, fee: (fee - fee.truncatingRemainder(dividingBy: 100)) / 10000, usedMB: floor(flow / 1024), updatedAt: Date())
    }
    func connectivity() async throws -> Bool {
        let (_, response) = try await session.data(from: URL(string: "https://www.bing.cn/")!)
        guard let http = response as? HTTPURLResponse else { return false }
        return (200..<400).contains(http.statusCode) && (http.url?.host?.contains("bing.") ?? false)
    }
    func history(year: Int, xuancheng: Bool) async throws -> [SchoolNetworkMonthRecord] {
        let html = try await request(URL(string: "Self/LoginAction.action", relativeTo: selfBase)!)
        if let checkcode = AcademicHTMLText.matches(html, "var\\s+checkcode\\s*=\\s*\"([^\"]+)\"").first?[1] {
            let tries = Int(AcademicHTMLText.matches(html, "var\\s+trytimes\\s*=\\s*\"([^\"]+)\"").first?[1] ?? "0") ?? 0
            guard tries < 3 else { throw CampusServiceError.invalidData("校园网自服务当前要求验证码；原版同样需先在官方页面完成验证") }
            _ = try await request(URL(string: "Self/js/random.js", relativeTo: selfBase)!)
            _ = try await request(URL(string: "Self/RandomCodeAction.action?randomNum=\(Double.random(in: 0..<1))", relativeTo: selfBase)!)
            let credentials = try LifeCredentialPolicy.networkCredentials(xuancheng: xuancheng)
            let hash = Insecure.MD5.hash(data: Data(credentials.password.utf8)).map { String(format: "%02x", $0) }.joined()
            let logged = try await request(URL(string: "Self/LoginAction.action", relativeTo: selfBase)!, fields: [("account", credentials.username), ("password", hash), ("code", ""), ("checkcode", checkcode), ("Submit", "登 录")], selfService: true)
            let doc = AcademicHTMLElement.parse(logged)
            let errors = doc.descendants.filter { ["fielderror1", "fielderror2"].contains($0.attributes["id"] ?? "") || $0.classes.contains("redtext") }.map(\.normalizedText).filter { !$0.isEmpty }
            if !errors.isEmpty { throw CampusServiceError.invalidData(errors.joined(separator: "；")) }
            if doc.descendants.contains(where: { $0.tag == "form" && $0.attributes["id"] == "loginform" }) { throw CampusServiceError.authenticationRequired("校园网自服务") }
        }
        let data = try await request(URL(string: "Self/MonthPayAction.action?type=1&year=\(year)", relativeTo: selfBase)!, selfService: true)
        return try Self.parseHistory(data)
    }
    func history(from start: Date, to end: Date, xuancheng: Bool) async throws -> [SchoolNetworkMonthRecord] {
        guard start <= end else { throw CampusServiceError.invalidData("结束日期不能早于开始日期") }
        let calendar = Calendar.current
        let firstYear = calendar.component(.year, from: start), lastYear = calendar.component(.year, from: end)
        var all: [SchoolNetworkMonthRecord] = []
        for year in firstYear...lastYear { all += try await history(year: year, xuancheng: xuancheng) }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        let low = formatter.string(from: start), high = formatter.string(from: end)
        var seen = Set<String>()
        return all.filter { String($0.startDate.prefix(10)) <= high && String($0.endDate.prefix(10)) >= low && seen.insert($0.id).inserted }.sorted { $0.startDate < $1.startDate }
    }
    static func parseHistory(_ html: String) throws -> [SchoolNetworkMonthRecord] {
        let doc = AcademicHTMLElement.parse(html)
        guard let table = doc.descendants.first(where: { $0.tag == "table" && $0.attributes["id"] == "example" }) else { throw CampusServiceError.invalidData("未找到校园网历史用量表，请刷新自服务登录状态") }
        return table.descendants.filter { $0.tag == "tr" }.compactMap { row in
            let values = row.children.filter { $0.tag == "td" }.map(\.normalizedText)
            guard values.count >= 8 else { return nil }
            return SchoolNetworkMonthRecord(startDate: values[0], endDate: values[1], packageName: values[2], baseFee: Double(values[3]) ?? 0, usageFee: Double(values[4]) ?? 0, durationMinutes: Int(values[5]) ?? 0, flowMB: Double(values[6]) ?? 0, billTime: values[7])
        }
    }
    private func request(_ url: URL, fields: [(String, String)]? = nil, selfService: Bool = false) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/144.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        if selfService { request.setValue("https://xywzz.hfut.edu.cn:8443/Self/LoginAction.action", forHTTPHeaderField: "Referer"); request.setValue("https://xywzz.hfut.edu.cn:8443", forHTTPHeaderField: "Origin") }
        if let fields {
            request.httpMethod = "POST"; request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
            request.httpBody = fields.map { "\($0.0.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")=\($0.1.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }.joined(separator: "&").data(using: .utf8)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw CampusServiceError.invalidResponse }
        if let text = String(data: data, encoding: .utf8) { return text }
        let gb18030 = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        guard let text = String(data: data, encoding: String.Encoding(rawValue: gb18030)) else { throw CampusServiceError.invalidData("校园网页面编码无法识别") }
        return text
    }
}
