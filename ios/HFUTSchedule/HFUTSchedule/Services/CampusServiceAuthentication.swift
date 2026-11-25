import Foundation

enum CampusServiceAuthentication {
    static func onePortalCallback(_ candidate: String, relativeTo base: URL? = nil) -> URL? {
        guard let url = URL(string:candidate,relativeTo:base)?.absoluteURL,
              url.host?.lowercased() == "one.hfut.edu.cn", url.user == nil, url.password == nil,
              ["http","https"].contains(url.scheme?.lowercased() ?? ""),
              let parts = URLComponents(url:url,resolvingAgainstBaseURL:false),
              let code = parts.queryItems?.first(where: { $0.name == "code" })?.value,
              !code.isEmpty, !code.contains(where: { $0.isWhitespace || $0.isNewline }) else { return nil }
        return url
    }

    static func secondClassSession(url: URL, status: Int, location: String?, setCookie: String,
                                   storage: HTTPCookieStorage) -> String? {
        guard url.host?.lowercased() == "dekt.hfut.edu.cn", (200..<300).contains(status), location == nil else { return nil }
        if let value = CASCookieParser.value(named:"SESSION",inCookieText:setCookie) { return "SESSION=\(value)" }
        // The server scopes this cookie to /scReports. Looking it up for /
        // drops a valid authenticated session after the redirect finishes.
        guard let value = storage.cookies(for:url)?.first(where: { $0.name == "SESSION" })?.value, !value.isEmpty else { return nil }
        return "SESSION=\(value)"
    }
}
