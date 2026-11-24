import Combine
import Foundation
import WebKit

struct WebFavoriteRecord: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var url: String
}

/// Shares the existing navigation-page collection format.
@MainActor
enum WebFavoriteStore {
    static let key = "webNavigationFavoritesV1"

    static func records(defaults: UserDefaults = .standard) -> [WebFavoriteRecord] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([WebFavoriteRecord].self, from: data)) ?? []
    }

    static func contains(_ url: URL, defaults: UserDefaults = .standard) -> Bool {
        records(defaults: defaults).contains { $0.url == url.absoluteString }
    }

    static func save(title: String, url: URL, defaults: UserDefaults = .standard) throws {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
            throw BrowserToolError.invalidURL
        }
        var items = records(defaults: defaults)
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = title.isEmpty ? (url.host ?? url.absoluteString) : title
        if let index = items.firstIndex(where: { $0.url == url.absoluteString }) { items[index].name = name }
        else { items.append(WebFavoriteRecord(name: name, url: url.absoluteString)) }
        defaults.set(try JSONEncoder().encode(items), forKey: key)
    }

    static func remove(_ url: URL, defaults: UserDefaults = .standard) throws {
        let items = records(defaults: defaults).filter { $0.url != url.absoluteString }
        defaults.set(try JSONEncoder().encode(items), forKey: key)
    }
}

enum BrowserToolError: LocalizedError, Equatable {
    case invalidURL, invalidCookie, noPage
    var errorDescription: String? {
        switch self {
        case .invalidURL: "请选择有效的 HTTP 或 HTTPS 网页"
        case .invalidCookie: "Cookie 格式应为 name=value; name2=value2，不能包含换行"
        case .noPage: "网页尚未准备好"
        }
    }
}

/// Commands act on the currently displayed WKWebView, not a second invisible browser.
@MainActor
final class PortalBrowserController: ObservableObject {
    weak var webView: WKWebView?
    @Published private(set) var currentURL: URL?
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var findMessage: String?
    @Published var errorMessage: String?

    func synchronize() {
        currentURL = webView?.url
        canGoBack = webView?.canGoBack ?? false
        canGoForward = webView?.canGoForward ?? false
    }
    func reload() { webView?.reload() }
    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }

    func find(_ text: String, backwards: Bool = false) {
        guard let webView else { findMessage = BrowserToolError.noPage.localizedDescription; return }
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.wraps = true
        webView.find(text, configuration: configuration) { [weak self] result in
            self?.findMessage = text.isEmpty ? nil : result.matchFound ? "已定位匹配文字" : "未找到匹配文字"
        }
    }

    func clearFind() { find("") }

    static func cookies(header: String, for url: URL) throws -> [HTTPCookie] {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), let host = url.host else {
            throw BrowserToolError.invalidURL
        }
        let header = header.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !header.isEmpty, header.utf8.count <= 32_768,
              header.rangeOfCharacter(from: .controlCharacters) == nil else { throw BrowserToolError.invalidCookie }
        let fragments = header.split(separator: ";", omittingEmptySubsequences: true)
        guard !fragments.isEmpty else { throw BrowserToolError.invalidCookie }
        return try fragments.map { fragment in
            let pair = fragment.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else { throw BrowserToolError.invalidCookie }
            let name = pair[0].trimmingCharacters(in: .whitespaces)
            let value = pair[1].trimmingCharacters(in: .whitespaces)
            let separators = CharacterSet(charactersIn: "()<>@,;:\\\"/[]?={} \t")
            guard !name.isEmpty, name.unicodeScalars.allSatisfy({ $0.isASCII && !separators.contains($0) }) else {
                throw BrowserToolError.invalidCookie
            }
            var properties: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .domain: host, .path: "/"]
            if url.scheme?.lowercased() == "https" { properties[.secure] = "TRUE" }
            guard let cookie = HTTPCookie(properties: properties) else { throw BrowserToolError.invalidCookie }
            return cookie
        }
    }

    func applyCookieHeader(_ header: String, to url: URL) async throws {
        guard let webView else { throw BrowserToolError.noPage }
        let cookies = try Self.cookies(header: header, for: url)
        let store = webView.configuration.websiteDataStore.httpCookieStore
        for cookie in cookies {
            await store.setCookie(cookie)
        }
        // An explicit user-supplied header applies only to this selected origin.
        var request = URLRequest(url: url)
        request.setValue(HTTPCookie.requestHeaderFields(with: cookies)["Cookie"], forHTTPHeaderField: "Cookie")
        webView.load(request)
    }
}
