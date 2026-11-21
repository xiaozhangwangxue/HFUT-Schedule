import CommonCrypto
import Darwin
import Foundation

enum WebVPNURLConverter {
    private static let root = URL(string: "https://webvpn.hfut.edu.cn/")!
    private static let key = Data("wrdvpnisthebest!".utf8)
    private static let keyHex = key.map { String(format: "%02x", $0) }.joined()

    static func convertedIfNeeded(_ url: URL, mode: AcademicConnectionMode) -> URL {
        guard mode == .webVPN, isCampusResource(url), !isWebVPNURL(url) else { return url }
        return convert(url) ?? url
    }

    /// Manual conversion accepts any complete HTTP(S) URL. Automatic navigation
    /// deliberately continues to use the narrower campus-resource allowlist.
    static func convert(_ text: String) -> URL? {
        normalizedInput(text).flatMap(convert)
    }

    static func convert(_ url: URL) -> URL? {
        guard let source = validatedComponents(url), let scheme = source.scheme?.lowercased(),
              let host = source.url?.host else { return nil }
        // Gateway login, portal and already encrypted URLs must not be wrapped
        // again, even when entered in the manual converter.
        if host.lowercased() == root.host { return source.url }
        guard let encrypted = crypt(Data(host.utf8), operation: CCOperation(kCCEncrypt)) else { return nil }
        let cipher = encrypted.map { String(format: "%02x", $0) }.joined()
        let port = source.port.map { "-\($0)" } ?? ""
        var target = URLComponents(url: root, resolvingAgainstBaseURL: false)!
        target.percentEncodedPath = "/\(scheme)\(port)/\(keyHex)\(cipher)" + (source.percentEncodedPath.isEmpty ? "/" : source.percentEncodedPath)
        target.percentEncodedQuery = source.percentEncodedQuery
        target.percentEncodedFragment = source.percentEncodedFragment
        return target.url
    }

    static func restore(_ text: String) -> URL? {
        normalizedInput(text).flatMap(restore)
    }

    /// Restores only this school's gateway URLs. Unlike the upstream string
    /// splitter, this also decodes the protocol's optional `-port` suffix.
    static func restore(_ url: URL) -> URL? {
        guard isWebVPNURL(url), let source = validatedComponents(url) else { return nil }
        let segments = source.percentEncodedPath.dropFirst().split(separator: "/", maxSplits: 2, omittingEmptySubsequences: false)
        guard segments.count >= 2 else { return nil }
        let route = String(segments[0]).lowercased()
        let protocolParts = route.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard let scheme = protocolParts.first.map(String.init), ["http", "https"].contains(scheme) else { return nil }
        let port: Int?
        if protocolParts.count == 2 {
            let text = String(protocolParts[1])
            guard text.range(of: #"^[0-9]{1,5}$"#, options: .regularExpression) != nil,
                  let value = Int(text), (1...65535).contains(value) else { return nil }
            port = value
        } else { port = nil }

        let token = String(segments[1])
        guard token.count > keyHex.count, token.count <= keyHex.count + 2048,
              token.prefix(keyHex.count).lowercased() == keyHex,
              let cipher = hexData(String(token.dropFirst(keyHex.count))),
              let plaintext = crypt(cipher, operation: CCOperation(kCCDecrypt)),
              let host = String(data: plaintext, encoding: .utf8), isValidHost(host) else { return nil }
        var target = URLComponents()
        target.scheme = scheme
        target.host = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        target.port = port
        target.percentEncodedPath = segments.count == 3 ? "/" + segments[2] : "/"
        target.percentEncodedQuery = source.percentEncodedQuery
        target.percentEncodedFragment = source.percentEncodedFragment
        guard let result = target.url, validatedComponents(result) != nil else { return nil }
        return result
    }

    /// Parses user input without guessing a scheme or treating pasted text as a
    /// relative URL. IDN hosts and Unicode paths are normalized by Foundation.
    static func normalizedInput(_ text: String) -> URL? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              text.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil,
              text.range(of: #"%(?![0-9a-fA-F]{2})"#, options: .regularExpression) == nil,
              let url = URLComponents(string: text)?.url,
              validatedComponents(url) != nil else { return nil }
        return url
    }

    static func isWebVPNURL(_ url: URL) -> Bool {
        guard let components = validatedComponents(url) else { return false }
        return components.scheme?.lowercased() == "https"
            && components.url?.host?.lowercased() == root.host
            && (components.port == nil || components.port == 443)
    }

    private static func validatedComponents(_ url: URL) -> URLComponents? {
        guard let components = URLComponents(url: url.absoluteURL, resolvingAgainstBaseURL: true),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              components.user == nil, components.password == nil,
              let host = components.url?.host, isValidHost(host),
              components.port.map({ (1...65535).contains($0) }) ?? true else { return nil }
        return components
    }

    private static func isValidHost(_ host: String) -> Bool {
        guard !host.isEmpty, host.utf8.count <= 1024 else { return false }
        if host.contains(":") {
            let address = host.hasPrefix("[") && host.hasSuffix("]") ? String(host.dropFirst().dropLast()) : host
            var bytes = in6_addr()
            return address.withCString { inet_pton(AF_INET6, $0, &bytes) == 1 }
        }
        // The ordinary URL API has already applied IDNA for conversion; a
        // restored Android URL may still contain a Unicode hostname.
        var canonical = URLComponents()
        canonical.scheme = "https"
        canonical.host = host
        guard let ascii = canonical.url?.host, ascii.utf8.count <= 254,
              ascii.range(of: #"^[A-Za-z0-9._-]+\.?$"#, options: .regularExpression) != nil else { return false }
        let domain = ascii.hasSuffix(".") ? String(ascii.dropLast()) : ascii
        return !domain.isEmpty && domain.split(separator: ".", omittingEmptySubsequences: false)
            .allSatisfy { !$0.isEmpty && $0.utf8.count <= 63 && !$0.hasPrefix("-") && !$0.hasSuffix("-") }
    }

    private static func hexData(_ text: String) -> Data? {
        guard !text.isEmpty, text.utf8.count.isMultiple(of: 2),
              text.range(of: #"^[0-9a-fA-F]+$"#, options: .regularExpression) != nil else { return nil }
        var data = Data()
        var index = text.startIndex
        while index < text.endIndex {
            let end = text.index(index, offsetBy: 2)
            guard let byte = UInt8(text[index..<end], radix: 16) else { return nil }
            data.append(byte)
            index = end
        }
        return data
    }

    static func isCampusResource(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if host == "hfut.edu.cn" || host.hasSuffix(".hfut.edu.cn") { return true }
        return [
            "121.251.19.62", "121.251.19.138", "210.45.246.53",
            "210.45.242.5", "210.45.242.57", "210.45.243.31"
        ].contains(host)
    }

    private static func crypt(_ input: Data, operation: CCOperation) -> Data? {
        var output = Data(count: input.count + kCCBlockSizeAES128)
        let capacity = output.count
        var cryptor: CCCryptorRef?
        let createStatus = key.withUnsafeBytes { keyBytes in
            CCCryptorCreateWithMode(
                operation, CCMode(kCCModeCFB), CCAlgorithm(kCCAlgorithmAES),
                CCPadding(ccNoPadding), keyBytes.baseAddress, keyBytes.baseAddress, key.count,
                nil, 0, 0, CCModeOptions(0), &cryptor
            )
        }
        guard createStatus == kCCSuccess, let cryptor else { return nil }
        defer { CCCryptorRelease(cryptor) }

        var moved = 0
        let updateStatus = output.withUnsafeMutableBytes { outputBytes in
            input.withUnsafeBytes { inputBytes in
                CCCryptorUpdate(
                    cryptor, inputBytes.baseAddress, input.count,
                    outputBytes.baseAddress, capacity, &moved
                )
            }
        }
        guard updateStatus == kCCSuccess else { return nil }
        output.removeSubrange(moved..<output.count)
        return output
    }
}
