import Foundation
import Security
import WebKit

/// Keeps the official campus web sessions shared between WKWebView and URLSession.
/// Session cookies are encrypted by the system Keychain so a single CAS login can
/// be reused after navigating between services or relaunching the app.
final class CampusSessionStore: @unchecked Sendable {
    static let shared = CampusSessionStore()

    private let lock = NSLock()
    private let keychainService = "com.xiaozhangwangxue.hfutschedule.campus-session"
    private let keychainAccount = "cookie-jar"
    private let sessionLifetime: TimeInterval = 12 * 60 * 60

    private init() {}

    func bootstrap() {
        restoreToSharedStorage()
        captureWebKit(WKWebsiteDataStore.default().httpCookieStore)
    }

    func restoreToSharedStorage() {
        for cookie in storedCookies() {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }

    func persist(_ cookies: [HTTPCookie]) {
        guard !cookies.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        var merged = readRecordsUnlocked()
            .filter { ($0.expiresAt ?? now.addingTimeInterval(sessionLifetime)) > now }
            .reduce(into: [String: CookieRecord]()) { result, record in
                result[record.identity] = record
            }
        for cookie in cookies {
            let record = CookieRecord(cookie: cookie, fallbackExpiration: now.addingTimeInterval(sessionLifetime))
            merged[record.identity] = record
            HTTPCookieStorage.shared.setCookie(cookie)
        }
        writeRecordsUnlocked(Array(merged.values))
    }

    func hydrateWebKit(_ cookieStore: WKHTTPCookieStore, completion: @escaping () -> Void) {
        let cookies = storedCookies()
        guard !cookies.isEmpty else {
            completion()
            return
        }
        let group = DispatchGroup()
        for cookie in cookies {
            HTTPCookieStorage.shared.setCookie(cookie)
            group.enter()
            cookieStore.setCookie(cookie) { group.leave() }
        }
        group.notify(queue: .main, execute: completion)
    }

    func captureWebKit(_ cookieStore: WKHTTPCookieStore, completion: (([HTTPCookie]) -> Void)? = nil) {
        cookieStore.getAllCookies { [weak self] cookies in
            self?.persist(cookies)
            DispatchQueue.main.async { completion?(cookies) }
        }
    }

    var allCookies: [HTTPCookie] {
        restoreToSharedStorage()
        return HTTPCookieStorage.shared.cookies ?? []
    }

    /// Removes only the selected service's cookies from both the live cookie jar
    /// and the persisted Keychain copy. This is used when the user explicitly
    /// opens the login screen and needs a fresh CAS form instead of an automatic
    /// redirect produced by a previously restored TGC.
    func removeCookies(forDomainSuffix suffix: String) {
        let normalized = suffix.lowercased()
        lock.lock()
        let kept = readRecordsUnlocked().filter { record in
            !record.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
                .hasSuffix(normalized.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
        }
        writeRecordsUnlocked(kept)
        lock.unlock()

        for cookie in HTTPCookieStorage.shared.cookies ?? [] where
            cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
                .hasSuffix(normalized.trimmingCharacters(in: CharacterSet(charactersIn: "."))) {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
    }

    private func storedCookies() -> [HTTPCookie] {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        let records = readRecordsUnlocked().filter {
            ($0.expiresAt ?? now.addingTimeInterval(sessionLifetime)) > now
        }
        if let data = try? JSONEncoder().encode(records) {
            writeKeychainDataUnlocked(data)
        }
        return records.compactMap(\.cookie)
    }

    private func readRecordsUnlocked() -> [CookieRecord] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return [] }
        return (try? JSONDecoder().decode([CookieRecord].self, from: data)) ?? []
    }

    private func writeRecordsUnlocked(_ records: [CookieRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        writeKeychainDataUnlocked(data)
    }

    private func writeKeychainDataUnlocked(_ data: Data) {
        let key: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        let update = SecItemUpdate(key as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard update == errSecItemNotFound else { return }
        var attributes = key
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        attributes[kSecValueData as String] = data
        SecItemAdd(attributes as CFDictionary, nil)
    }
}

private struct CookieRecord: Codable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let secure: Bool
    let httpOnly: Bool
    let expiresAt: Date?

    init(cookie: HTTPCookie, fallbackExpiration: Date) {
        name = cookie.name
        value = cookie.value
        domain = cookie.domain
        path = cookie.path
        secure = cookie.isSecure
        httpOnly = cookie.isHTTPOnly
        expiresAt = cookie.expiresDate ?? fallbackExpiration
    }

    var identity: String { "\(name)|\(domain.lowercased())|\(path)" }

    var cookie: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path,
            .secure: secure ? "TRUE" : "FALSE"
        ]
        if let expiresAt { properties[.expires] = expiresAt }
        if httpOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
        return HTTPCookie(properties: properties)
    }
}
