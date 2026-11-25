import Foundation

/// HTTPURLResponse can coalesce repeated Set-Cookie fields differently across
/// OS versions. Split only at a new cookie pair, never at the comma in Expires.
enum CASCookieParser {
    static func headerValues(from response: HTTPURLResponse) -> [String] {
        let values = response.allHeaderFields.flatMap { field -> [String] in
            guard String(describing: field.key).caseInsensitiveCompare("Set-Cookie") == .orderedSame else { return [] }
            if let value = field.value as? String { return [value] }
            return field.value as? [String] ?? []
        }
        return values.isEmpty ? response.value(forHTTPHeaderField: "Set-Cookie").map { [$0] } ?? [] : values
    }

    static func split(_ header: String) -> [String] {
        let pattern = #"[\r\n]+|,(?=[ \t]*[!#$%&'*+\-.^_`|~A-Za-z0-9]+[ \t]*=)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let separated = expression.stringByReplacingMatches(in: header,
            range: NSRange(header.startIndex..., in: header), withTemplate: "\n")
        return separated.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static func cookies(from response: HTTPURLResponse) -> [HTTPCookie] {
        guard let url = response.url else { return [] }
        return cookies(headerValues: headerValues(from: response), url: url)
    }

    static func cookies(headerValues: [String], url: URL) -> [HTTPCookie] {
        headerValues.flatMap(split).flatMap {
            HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": $0], for: url)
        }
    }

    /// Use this response's raw fields for CAS preparation. A cookie jar may
    /// contain a previous challenge and must never supply a missing fresh key.
    static func value(named name: String, in response: HTTPURLResponse) -> String? {
        for field in headerValues(from: response) {
            if let value = value(named: name, inCookieText: field) { return value }
        }
        return nil
    }

    static func value(named name: String, inCookieText text: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let pattern = "(?:^|[;,\\r\\n])[ \\t]*" + escaped + #"[ \t]*=[ \t]*(?:"([^"\r\n]*)"|([^;,\s"\\]+))"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        for group in 1...2 where match.range(at: group).location != NSNotFound {
            guard let range = Range(match.range(at: group), in: text) else { continue }
            let value = String(text[range])
            guard !value.isEmpty, !value.contains(where: { $0.isWhitespace || $0.isNewline || $0.asciiValue.map { $0 < 0x21 || $0 == 0x7f } == true }),
                  !value.contains(";"), !value.contains(","), !value.contains("\\") else { return nil }
            return value
        }
        return nil
    }

    static func virtualValue(named name: String, data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        // The current gateway returns plain Cookie text; some gateways wrap it
        // as a JSON string. Decode the envelope before reading cookie pairs.
        let decoded = (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)) as? String
        return value(named: name, inCookieText: decoded ?? text)
    }

    static func grantingCookie(fromVirtualData data: Data) -> HTTPCookie? {
        for name in ["TGC", "CASTGC"] {
            if let value = virtualValue(named:name,data:data) {
                return HTTPCookie(properties:[.name:name,.value:value,.domain:"cas.hfut.edu.cn",
                    .path:"/cas/",.secure:"TRUE"])
            }
        }
        return nil
    }
}
