import Foundation

/// Guagua returns thousandths of a yuan; card endpoints return cents instead.
enum ShowerMoney {
    static func yuan(_ raw: Any?) -> Double {
        let number = (raw as? NSNumber)?.doubleValue ?? Double(raw as? String ?? "") ?? 0
        return number / 1000
    }
}

enum StudentPhone {
    static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        var digits = value.folding(options: .widthInsensitive, locale: Locale(identifier: "zh_CN"))
            .filter { $0.isASCII && $0.isNumber }
        if digits.count == 13 && digits.hasPrefix("86") { digits.removeFirst(2) }
        guard digits.count == 11, digits.first == "1", let second = digits.dropFirst().first, "3456789".contains(second) else { return nil }
        return digits
    }
    static func from(_ info: AcademicStudentInfo?) -> String? {
        guard let fields = info?.fields else { return nil }
        for label in ["手机", "手机号", "手机号码", "联系电话", "移动电话", "mobile", "phone", "电话"] {
            if let phone = normalized(fields[label]) { return phone }
        }
        for (label, value) in fields where label.contains("手机") || label.lowercased().contains("mobile") {
            if let phone = normalized(value) { return phone }
        }
        return nil
    }
    static func autofill(_ current: String, info: AcademicStudentInfo?) -> String {
        current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? from(info) ?? current : current
    }
}

enum CampusMailResponse {
    static func url(from data: Data) throws -> URL? {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CampusServiceError.invalidResponse }
        let message = root["msg"] as? String ?? root["message"] as? String ?? ""
        let code = root["code"] as? Int
        if root["success"] as? Bool == false || [401, 403].contains(code ?? 0)
            || (root["data"] == nil && !message.isEmpty && message.lowercased() != "success") {
            throw CampusServiceError.invalidData(root["msg"] as? String ?? root["message"] as? String ?? "邮箱登录链接获取失败，请刷新登录状态")
        }
        guard let value = root["data"] as? String, !value.isEmpty else { return nil }
        guard let url = URL(string: value), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
            throw CampusServiceError.invalidData("校方返回了无效的邮箱链接，请重新获取")
        }
        return url
    }
}

/// Read the same input schema as charge-app, rather than assuming that fee 26
/// calls its phone field telPhone (deployments use different field codes).
enum HuiXinPhoneFeeForm {
    static func fields(metadata: Data, itemID: Int, phone: String) throws -> [(String, String)] {
        guard let phone = StudentPhone.normalized(phone) else { throw CampusServiceError.invalidData("请输入正确的 11 位手机号") }
        guard let root = try JSONSerialization.jsonObject(with: metadata) as? [String: Any],
              let map = root["map"] as? [String: Any], let total = map["total"] as? [[String: Any]], !total.isEmpty else {
            throw CampusServiceError.invalidData("慧新易校未返回洗衣账号查询表单，请打开官方洗衣缴费核对账号")
        }
        // A single phone/account input is sufficient. If a deployment requires
        // building or room selection as well, don't query an invented account.
        guard total.count == 1, let field = total.first, let code = field["code"] as? String, !code.isEmpty else {
            throw CampusServiceError.invalidData("该洗衣账户还需选择区域或房间，请打开官方洗衣缴费完成选择")
        }
        let level = (field["level"] as? NSNumber)?.stringValue ?? field["level"] as? String ?? "1"
        return [("feeitemid", "\(itemID)"), ("type", "IEC"), ("level", level), (code, phone)]
    }
}

enum PhoneFeeService: String { case bathing, laundry }

@MainActor
final class PhoneFeeBalanceModel: ObservableObject {
    @Published private(set) var results: [String: String] = [:]
    @Published private(set) var error: String?
    @Published private(set) var loading = false
    @Published private(set) var updatedAt: Date?
    private var currentKey = ""
    private let service: PhoneFeeService
    private let fetch: (HuiXinFeeKind) async throws -> [String: String]
    init(service: PhoneFeeService, fetch: @escaping (HuiXinFeeKind) async throws -> [String: String] = { try await CampusServiceClient.shared.fetchFee($0) }) {
        self.service = service; self.fetch = fetch
    }
    var summary: String {
        if let balance = PhoneFeeAmount.balance(results) { return balance }
        if error != nil { return "暂未获取" }
        return loading ? "正在查询" : results.isEmpty ? "待查询" : "未返回余额"
    }
    func refresh(campus: AppState.Campus, phone: String, force: Bool = false) async {
        let normalized = StudentPhone.normalized(phone)
        let key = "\(campus.rawValue)|\(normalized ?? phone)"
        if key != currentKey { currentKey = key; results = [:]; updatedAt = nil; error = nil; loading = false }
        if service == .laundry && campus != .hefei { error = "慧新易校洗衣余额目前仅支持合肥校区"; return }
        guard let normalized else { error = "个人资料暂未返回可用手机号，请刷新登录状态后重试"; return }
        guard !loading, force || updatedAt.map({ Date().timeIntervalSince($0) >= 60 }) != false else { return }
        loading = true; error = nil
        let kind: HuiXinFeeKind = service == .laundry ? .laundryHefei(phone: normalized) : campus == .hefei ? .bathingHefei(phone: normalized) : .bathingXuancheng(phone: normalized)
        do {
            let value = try await fetch(kind)
            guard currentKey == key else { return }
            results = value; updatedAt = Date()
        } catch is CancellationError {
            if currentKey == key { loading = false }; return
        } catch {
            guard currentKey == key else { return }
            self.error = error.localizedDescription
        }
        if currentKey == key { loading = false }
    }
}

/// Multiple weekly meetings of one lesson should be one quick lookup.
enum OwnCourseLookup {
    static func courses(_ courses: [Course]) -> [Course] {
        var seen = Set<String>()
        return courses.filter { !$0.name.isEmpty && seen.insert($0.details?.code.flatMap { $0.isEmpty ? nil : $0 } ?? $0.name).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

enum WebNavigationURL {
    static func normalized(_ text: String) -> URL? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains(where: \.isWhitespace) else { return nil }
        let candidate = value.contains("://") ? value : "https://" + value
        guard let url = URL(string: candidate), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), let host = url.host, host.contains("."), !host.hasPrefix("."), !host.hasSuffix(".") else { return nil }
        return url
    }
}

/// HuiXin bathing calls its balance "现金金额（单位：元）"; laundry uses
/// "账户余额". Never pick a phone/account identifier or the gifted amount.
enum PhoneFeeAmount {
    static func balance(_ fields: [String: String]) -> String? {
        let names = fields.keys.sorted()
        let key = names.first { $0.contains("余额") && !$0.contains("赠") }
            ?? names.first { $0.contains("现金金额") }
            ?? names.first { $0.contains("可用金额") }
        guard let key, let raw = fields[key], !raw.isEmpty else { return nil }
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "￥", with: "").replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: "元", with: "").replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = Double(cleaned), value.isFinite { return String(format: "¥%.2f", value) }
        return raw
    }
}
