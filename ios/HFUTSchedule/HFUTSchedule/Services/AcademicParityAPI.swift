import Foundation
import Security

/// Additional academic endpoints, kept separate from the timetable synchronizer.
/// Request paths and field names follow network-api at upstream 9670096e.
struct CommunityGradeResult: Decodable {
    let gpa: Double
    let classRanking: String
    let majorRanking: String
    let scoreInfoDTOList: [Score]
    struct Score: Decodable, Identifiable {
        var id: String { "\(courseName)|\(score)|\(credit)" }
        let courseName: String
        let score: Double
        let credit: Double
        let gpa: Double
        let pass: Bool
    }
}

extension OfficialCampusAPIClient {
    func fetchCommunityGrades(startYear: Int, term: Int) async throws -> CommunityGradeResult {
        let data = try await communityAuthorizedData(path: "api/business/score/scoreselect?xn=\(startYear)-\(startYear + 1)&xq=\(term)")
        struct Envelope: Decodable { let result: CommunityGradeResult }
        return try JSONDecoder().decode(Envelope.self, from: data).result
    }
}

struct PublicExamNotice: Identifiable, Hashable {
    var id: String { url.absoluteString }
    let title: String
    let date: String
    let url: URL
}

enum AcademicHTMLText {
    static func matches(_ text: String, _ pattern: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { result in
            (0..<result.numberOfRanges).map { i in Range(result.range(at: i), in: text).map { String(text[$0]) } ?? "" }
        }
    }
    static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func attribute(_ html: String, _ name: String) -> String {
        matches(html, "\\b\(name)\\s*=\\s*[\"']([^\"']*)[\"']").first?[1] ?? ""
    }
}

enum PublicExamNoticeClient {
    static func fetch(xuancheng: Bool, page: Int) async throws -> [PublicExamNotice] {
        let base = URL(string: xuancheng ? "https://xcjwb.hfut.edu.cn/" : "https://news.hfut.edu.cn/")!
        var request: URLRequest
        if xuancheng {
            request = URLRequest(url: URL(string: "1178/list\(page).htm", relativeTo: base)!)
        } else {
            request = URLRequest(url: URL(string: "zq_search.jsp?wbtreeid=1137", relativeTo: base)!)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let keyword = Data("周考试安排".utf8).base64EncodedString()
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
            request.httpBody = "sitenewskeycode=\(keyword.addingPercentEncoding(withAllowedCharacters: allowed) ?? keyword)&currentnum=\(page)".data(using: .utf8)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let html = String(data: data, encoding: .utf8) else {
            throw AcademicClientError.invalidData("考试通知页面读取失败")
        }
        let rows = AcademicHTMLText.matches(html, xuancheng ? "<tr\\b[^>]*>(.*?)</tr>" : "<li\\b[^>]*>(.*?)</li>")
        var seen = Set<String>()
        return rows.compactMap { row in
            let content = row[1]
            guard let anchor = AcademicHTMLText.matches(content, "<a\\b([^>]*)>(.*?)</a>").first else { return nil }
            let href = AcademicHTMLText.attribute(anchor[1], "href")
            guard !href.isEmpty, let url = URL(string: href, relativeTo: base)?.absoluteURL else { return nil }
            if !xuancheng && url.host?.lowercased() != "jwc.hfut.edu.cn" { return nil }
            let titleAttribute = AcademicHTMLText.attribute(anchor[1], "title")
            let title = AcademicHTMLText.clean(titleAttribute.isEmpty ? anchor[2] : titleAttribute)
            guard !title.isEmpty, seen.insert(url.absoluteString).inserted else { return nil }
            let date = AcademicHTMLText.matches(content, "\\d{4}[-/.]\\d{1,2}[-/.]\\d{1,2}").first?[0] ?? ""
            return PublicExamNotice(title: title, date: date, url: url)
        }
    }
}

struct XiaoWuXingSchool: Decodable, Identifiable {
    var id: Int64 { schoolCode }
    let schoolCode: Int64
    let schoolName: String
    let iconUrl: String
}
struct XiaoWuXingFunction: Decodable, Identifiable {
    var id: String { vcPrintTypeId }
    let vcPrintTypeId: String
    let printType: String
    let fileProerty: String
}

actor XiaoWuXingClient {
    static let shared = XiaoWuXingClient()
    private let base = URL(string: "https://xwx.gzzmedu.com:9080/")!
    private let keychainService = "HFUTSchedule.XiaoWuXing"
    private var sessionInfo: SessionInfo?
    private struct SessionInfo: Codable { let schoolCode: Int64; let userId: String; let token: String }

    func schools() async throws -> [XiaoWuXingSchool] {
        let root = try await post("getSchoolList", body: ["schoolCode": "", "userId": "", "type": 1])
        let rows = (root["data"] as? [[String: Any]] ?? []).flatMap { $0["list"] as? [[String: Any]] ?? [] }
        return try JSONDecoder().decode([XiaoWuXingSchool].self, from: JSONSerialization.data(withJSONObject: rows))
    }
    func login(schoolCode: Int64, username: String, password: String) async throws {
        let root = try await post("api/login/user", body: ["schoolCode": schoolCode, "userId": username, "password": password, "loginType": 3])
        guard let token = root["token"] as? String, !token.isEmpty else { throw AcademicClientError.invalidData("校务行未返回有效登录令牌") }
        let value = SessionInfo(schoolCode: schoolCode, userId: username, token: token)
        let data = try JSONEncoder().encode(value)
        let key: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: "session"]
        SecItemDelete(key as CFDictionary)
        var item = key; item[kSecValueData as String] = data; item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw AcademicClientError.invalidData("无法安全保存校务行会话") }
        sessionInfo = value
    }
    func logout() {
        sessionInfo = nil
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: "session"] as CFDictionary)
    }
    func functions() async throws -> [XiaoWuXingFunction] {
        let info = try session()
        let root = try await post("api/office-service-ms/printType", body: ["schoolCode": info.schoolCode, "userId": info.userId], token: info.token)
        return try JSONDecoder().decode([XiaoWuXingFunction].self, from: JSONSerialization.data(withJSONObject: root["data"] as? [Any] ?? []))
    }
    func preview(_ function: XiaoWuXingFunction) async throws -> Data {
        let info = try session()
        let root = try await post("api/office-service-ms/eDoc/getPdfPic", body: ["schoolCode": info.schoolCode, "userId": info.userId, "filePropertyType": Int(function.fileProerty) ?? 0, "fileProperty": function.vcPrintTypeId, "pm": "1"], token: info.token)
        guard let raw = root["smallImageList"] as? String,
              let data = Data(base64Encoded: raw.components(separatedBy: ",").last ?? raw, options: .ignoreUnknownCharacters) else { throw AcademicClientError.invalidData("校务行未返回预览图片") }
        return data
    }
    private func session() throws -> SessionInfo {
        if let sessionInfo { return sessionInfo }
        var result: CFTypeRef?
        let status = SecItemCopyMatching([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: "session", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne] as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, let value = try? JSONDecoder().decode(SessionInfo.self, from: data) else { throw AcademicClientError.invalidData("请先登录校务行") }
        sessionInfo = value
        return value
    }
    private func post(_ path: String, body: [String: Any], token: String? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: path, relativeTo: base)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue(token, forHTTPHeaderField: "X-Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AcademicClientError.invalidData("校务行接口读取失败") }
        guard String(describing: root["errcode"] ?? "") == "0" else { throw AcademicClientError.invalidData(root["errmsg"] as? String ?? root["message"] as? String ?? "校务行拒绝了请求") }
        guard let result = root["result"] as? [String: Any] else { throw AcademicClientError.invalidData("校务行返回格式无法识别") }
        return result
    }
}

/// UI failures only: no request bodies, account inputs or session material.
enum AcademicServiceDiagnostics {
    static func record(context: String, error: Error) {
        Task { @MainActor in PlatformDiagnosticsStore.shared.record(context: context, error: error) }
    }
}
