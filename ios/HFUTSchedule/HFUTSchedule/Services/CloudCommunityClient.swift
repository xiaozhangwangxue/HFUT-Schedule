import Foundation
import Combine
import UIKit

struct CloudCommunityEvent: Codable, Identifiable, Hashable {
    var id: Int
    var name: String
    var description: String?
    var timeDescription: String
    var startTime: String
    var endTime: String
    var contributorEmail: String?
    var contributorClass: String?
    var applicableClasses: String
    var createdTime: String?
    var url: String?
    var campus: String
    var type: String
    enum CodingKeys: String, CodingKey {
        case id, name, description, url, campus, type
        case timeDescription = "time_description", startTime = "start_time", endTime = "end_time"
        case contributorEmail = "contributor_email", contributorClass = "contributor_class"
        case applicableClasses = "applicable_classes", createdTime = "created_time"
    }
    var start: Date? { CloudCommunityDate.parse(startTime) }
    var end: Date? { CloudCommunityDate.parse(endTime) }
    var created: Date? { createdTime.flatMap(CloudCommunityDate.parse) }
    var isValid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && start != nil && end != nil && end! >= start! && ["SCHEDULE", "NET_COURSE"].contains(type) }
    var localGroupID: String { "supabase:\(id)" }
    var relevantDate: Date { (type == "NET_COURSE" ? end : start) ?? .distantFuture }
    var safeURL: URL? {
        guard let url, let value = URL(string: url), ["https", "http"].contains(value.scheme ?? ""), value.host != nil else { return nil }
        return value
    }
    func applies(to className: String, campus userCampus: String) -> Bool {
        let classes = applicableClasses.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let matchesClass = classes.isEmpty || classes.contains("EMPTY") || (!className.isEmpty && classes.contains { $0.contains(className) })
        return matchesClass && (campus == "DEFAULT" || campus == userCampus)
    }
    func localEvent(existingID: UUID? = nil) -> CustomEvent? {
        guard isValid, let start, let end else { return nil }
        return CustomEvent(id: existingID ?? UUID(), title: name,
            detail: [description == "NULL" ? nil : description, safeURL?.absoluteString].compactMap { $0 }.joined(separator: "\n"),
            location: timeDescription, start: start, end: end, kind: type == "NET_COURSE" ? .deadline : .event, groupID: localGroupID)
    }
    func contributionBody(email: String, contributorClass: String) -> [String: Any] {
        ["name": name, "description": description.map { $0 as Any } ?? NSNull(), "time_description": timeDescription,
         "start_time": startTime, "end_time": endTime, "contributor_email": email,
         "contributor_class": contributorClass, "applicable_classes": applicableClasses,
         "campus": campus, "type": type, "url": url.map { $0 as Any } ?? NSNull()]
    }
}

enum CloudCommunityDate {
    static func parse(_ value: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: value) { return date }
        // Upstream stores UTC timestamps without a zone suffix.
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
    static func string(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.string(from: date)
    }
}

struct CloudCommunitySession: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Double?
    var user: User?
    struct User: Codable { let email: String? }
    enum CodingKeys: String, CodingKey { case accessToken = "access_token", refreshToken = "refresh_token", expiresAt = "expires_at", user }
}

enum CloudCommunityError: LocalizedError {
    case loginRequired, invalidEmail, invalidResponse, server(String), invalidEvent, localSaveFailed
    var errorDescription: String? {
        switch self {
        case .loginRequired: "请先登录云共建账号"
        case .invalidEmail: "请输入有效的合工大学号或 @mail.hfut.edu.cn 邮箱"
        case .invalidResponse: "云共建返回了无法识别的数据"
        case .server(let text): text
        case .invalidEvent: "日程名称、类型或起止时间无效"
        case .localSaveFailed: "本地日程保存失败，未记录为已下载"
        }
    }
}

@MainActor
final class CloudCommunityClient: ObservableObject {
    static let shared = CloudCommunityClient()
    @Published private(set) var events: [CloudCommunityEvent] = []
    @Published private(set) var myEvents: [CloudCommunityEvent] = []
    @Published private(set) var hasSession = false
    @Published private(set) var accountEmail = ""
    @Published private(set) var loading = false
    @Published private(set) var myLoading = false
    @Published private(set) var forkCounts: [Int: Int] = [:]
    @Published private(set) var importedVersions: [Int: CloudCommunityEvent] = [:]
    private var auth: CloudCommunitySession?
    private let session: URLSession
    private let baseURL: URL
    private let anonymousKey: String
    private let credentialAccount: String
    private let defaults: UserDefaults
    private var refreshTask: Task<CloudCommunitySession, Error>?
    private var authGeneration = UUID()
    init(session: URLSession = .shared, baseURL: URL = SupabasePublicConfiguration.baseURL,
         anonymousKey: String = SupabasePublicConfiguration.anonymousKey, credentialAccount: String = "supabase-community-session", defaults: UserDefaults = .standard) {
        self.session = session; self.baseURL = baseURL; self.anonymousKey = anonymousKey; self.credentialAccount = credentialAccount; self.defaults = defaults
        if let data = defaults.data(forKey: "cloudCommunityImportsV1") { importedVersions = (try? JSONDecoder().decode([Int: CloudCommunityEvent].self, from: data)) ?? [:] }
        if let text = AppSecretStore.read(credentialAccount), let data = text.data(using: .utf8), let stored = try? JSONDecoder().decode(CloudCommunitySession.self, from: data) {
            auth = stored; hasSession = !stored.accessToken.isEmpty; accountEmail = stored.user?.email ?? ""
        }
    }
    static func schoolEmail(_ input: String) throws -> String {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let id = value.hasSuffix("@mail.hfut.edu.cn") ? String(value.dropLast("@mail.hfut.edu.cn".count)) : value
        guard id.count == 10, id.utf8.allSatisfy({ (48...57).contains($0) }) else { throw CloudCommunityError.invalidEmail }
        return id + "@mail.hfut.edu.cn"
    }
    func signIn(account: String, password: String) async throws {
        let email = try Self.schoolEmail(account)
        refreshTask?.cancel(); refreshTask = nil; authGeneration = UUID()
        let generation = authGeneration
        let data = try await request(path: "auth/v1/token", method: "POST", query: [.init(name: "grant_type", value: "password")], body: ["email": email, "password": password])
        guard generation == authGeneration else { throw CancellationError() }
        var result = try JSONDecoder().decode(CloudCommunitySession.self, from: data)
        if result.user?.email == nil { result.user = .init(email: email) }
        try persist(result)
    }
    func signUp(account: String, password: String) async throws -> Bool {
        let email = try Self.schoolEmail(account)
        let data = try await request(path: "auth/v1/signup", method: "POST", body: ["email": email, "password": password])
        if let result = try? JSONDecoder().decode(CloudCommunitySession.self, from: data), !result.accessToken.isEmpty { try persist(result); return true }
        // Supabase normally sends an activation message to the school mailbox.
        return false
    }
    func signOut() {
        refreshTask?.cancel(); refreshTask = nil; authGeneration = UUID()
        auth = nil; hasSession = false; accountEmail = ""; myEvents = []
        AppSecretStore.write("", account: credentialAccount)
    }
    func verifySession() async throws {
        _ = try await authorized(path: "functions/v1/check-login")
    }
    func refreshSession() async throws {
        _ = try await refreshed()
    }
    private func refreshed() async throws -> CloudCommunitySession {
        if let refreshTask { return try await refreshTask.value }
        guard let auth, !auth.refreshToken.isEmpty else { throw CloudCommunityError.loginRequired }
        let generation = authGeneration
        let task = Task {
            let data = try await self.request(path: "auth/v1/token", method: "POST", query: [.init(name: "grant_type", value: "refresh_token")], body: ["refresh_token": auth.refreshToken])
            return try JSONDecoder().decode(CloudCommunitySession.self, from: data)
        }
        refreshTask = task
        defer { refreshTask = nil }
        var result = try await task.value
        guard generation == authGeneration else { throw CancellationError() }
        if result.user?.email == nil { result.user = auth.user }
        try persist(result)
        return result
    }
    func loadEvents(includeExpired: Bool = false) async throws {
        importedVersions = defaults.data(forKey: "cloudCommunityImportsV1").flatMap { try? JSONDecoder().decode([Int: CloudCommunityEvent].self, from: $0) } ?? [:]
        guard !loading else { return }; loading = true; defer { loading = false }
        let query: [URLQueryItem] = includeExpired ? [] : [.init(name: "end_time", value: "gt." + CloudCommunityDate.string(Date()))]
        let data = try await request(path: "rest/v1/event", query: query)
        events = try JSONDecoder().decode([CloudCommunityEvent].self, from: data).filter(\.isValid)
    }
    func loadMyEvents() async throws {
        guard hasSession else { throw CloudCommunityError.loginRequired }
        guard !myLoading else { return }; myLoading = true; defer { myLoading = false }
        _ = try await authorized(path: "functions/v1/check-login")
        let data = try await authorized(path: "rest/v1/event", query: [.init(name: "contributor_email", value: "eq." + accountEmail)])
        myEvents = try JSONDecoder().decode([CloudCommunityEvent].self, from: data).filter(\.isValid)
    }
    func contribute(_ event: CloudCommunityEvent, className: String, update: Bool) async throws {
        guard event.isValid else { throw CloudCommunityError.invalidEvent }
        let body = event.contributionBody(email: accountEmail, contributorClass: className)
        if update {
            guard event.contributorEmail?.lowercased() == accountEmail.lowercased() else { throw CloudCommunityError.loginRequired }
            _ = try await authorized(path: "rest/v1/event", method: "PATCH", query: [.init(name: "id", value: "eq.\(event.id)")], body: body)
        } else { _ = try await authorized(path: "rest/v1/event", method: "POST", body: body, prefer: "return=representation") }
        try await loadMyEvents()
    }
    func delete(_ event: CloudCommunityEvent) async throws {
        guard event.contributorEmail?.lowercased() == accountEmail.lowercased() else { throw CloudCommunityError.loginRequired }
        _ = try await authorized(path: "rest/v1/event", method: "DELETE", query: [.init(name: "id", value: "eq.\(event.id)")])
        myEvents.removeAll { $0.id == event.id }; events.removeAll { $0.id == event.id }
    }
    func loadForkCount(_ id: Int) async {
        guard hasSession else { return }
        if let data = try? await authorized(path: "rest/v1/rpc/get_event_fork_count", method: "POST", body: ["target_event_id": id]) {
            if let count = try? JSONDecoder().decode(Int.self, from: data) { forkCounts[id] = count }
        }
    }
    func importEvent(_ event: CloudCommunityEvent, into store: CustomEventStore) async throws -> Bool {
        let previous = store.events.first { $0.groupID == event.localGroupID }
        guard let local = event.localEvent(existingID: previous?.id) else { throw CloudCommunityError.invalidEvent }
        guard store.save(local) else { throw CloudCommunityError.localSaveFailed }
        importedVersions[event.id] = event
        defaults.set(try JSONEncoder().encode(importedVersions), forKey: "cloudCommunityImportsV1")
        if previous == nil && hasSession {
            // Local success remains valid even if the optional download-count request fails.
            _ = try? await authorized(path: "rest/v1/event_fork", method: "POST", body: ["event_id": event.id, "user_email": accountEmail])
        }
        return previous != nil
    }
    private func persist(_ value: CloudCommunitySession) throws {
        guard !value.accessToken.isEmpty, !value.refreshToken.isEmpty else { throw CloudCommunityError.invalidResponse }
        AppSecretStore.write(String(decoding: try JSONEncoder().encode(value), as: UTF8.self), account: credentialAccount)
        auth = value; hasSession = true; accountEmail = value.user?.email ?? ""
    }
    private func authorized(path: String, method: String = "GET", query: [URLQueryItem] = [], body: [String: Any]? = nil, prefer: String? = nil) async throws -> Data {
        guard var auth else { throw CloudCommunityError.loginRequired }
        if let expiry = auth.expiresAt, expiry <= Date().timeIntervalSince1970 + 30 { auth = try await refreshed() }
        do { return try await request(path: path, method: method, query: query, body: body, token: auth.accessToken, prefer: prefer) }
        catch CloudHTTPError.unauthorized {
            let next = try await refreshed()
            return try await request(path: path, method: method, query: query, body: body, token: next.accessToken, prefer: prefer)
        }
    }
    private func request(path: String, method: String = "GET", query: [URLQueryItem] = [], body: [String: Any]? = nil, token: String? = nil, prefer: String? = nil) async throws -> Data {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!); request.httpMethod = method; request.timeoutInterval = 30
        request.setValue(anonymousKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { PlatformDiagnosticsStore.shared.record(context: "云共建网络请求", error: error); throw error }
        guard let response = response as? HTTPURLResponse, data.count <= 20_971_520 else { throw CloudCommunityError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 401 && token != nil { throw CloudHTTPError.unauthorized }
            PlatformDiagnosticsStore.shared.record(context: "云共建服务响应", error: NSError(domain: "CloudCommunityHTTP", code: response.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "云共建服务返回 HTTP \(response.statusCode)，原始响应未记录。 "]))
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let text = object?["msg"] as? String ?? object?["message"] as? String ?? object?["error_description"] as? String
            throw CloudCommunityError.server(text.map { String($0.prefix(500)) } ?? "云共建请求失败（\(response.statusCode)）")
        }
        return data
    }
    private enum CloudHTTPError: Error { case unauthorized }

    private var reportedThisLaunch = false
    func reportAnonymousUsageIfAllowed(defaults: UserDefaults = .standard) async {
        #if DEBUG || targetEnvironment(simulator)
        return
        #else
        guard !reportedThisLaunch, defaults.object(forKey: AppSettingsKey.dataReporting) as? Bool ?? true else { return }
        reportedThisLaunch = true
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let code = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0
        _ = try? await request(path: "rest/v1/user_app_usage", method: "POST", body: [
            "user_name": "iOS匿名用户", "student_id": "空", "campus": "空", "department": "空",
            "system_version": ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
            "app_version_name": version, "app_version_code": code, "device_name": "iOS"
        ])
        #endif
    }
}
