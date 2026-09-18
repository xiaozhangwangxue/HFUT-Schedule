import CommonCrypto
import Foundation

enum WebVPNURLConverter {
    private static let root = URL(string: "https://webvpn.hfut.edu.cn/")!
    private static let key = Data("wrdvpnisthebest!".utf8)

    static func convertedIfNeeded(_ url: URL, mode: AcademicConnectionMode) -> URL {
        guard mode == .webVPN, isCampusResource(url), url.host != root.host else { return url }
        return convert(url) ?? url
    }

    static func convert(_ url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, let cipher = encryptHost(host) else { return nil }
        let port = url.port.map { "-\($0)" } ?? ""
        let keyHex = key.map { String(format: "%02x", $0) }.joined()
        var text = "https://webvpn.hfut.edu.cn/\(scheme)\(port)/\(keyHex)\(cipher)"
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let path = components?.percentEncodedPath ?? url.path
        text += path.isEmpty ? "/" : path
        if let query = components?.percentEncodedQuery { text += "?\(query)" }
        if let fragment = url.fragment { text += "#\(fragment)" }
        return URL(string: text)
    }

    static func isCampusResource(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if host == "hfut.edu.cn" || host.hasSuffix(".hfut.edu.cn") { return true }
        return [
            "121.251.19.62", "121.251.19.138", "210.45.246.53",
            "210.45.242.5", "210.45.242.57", "210.45.243.31"
        ].contains(host)
    }

    private static func encryptHost(_ host: String) -> String? {
        let input = Data(host.utf8)
        var output = Data(count: input.count + kCCBlockSizeAES128)
        let capacity = output.count
        var cryptor: CCCryptorRef?
        let createStatus = key.withUnsafeBytes { keyBytes in
            CCCryptorCreateWithMode(
                CCOperation(kCCEncrypt), CCMode(kCCModeCFB), CCAlgorithm(kCCAlgorithmAES),
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
        return output.map { String(format: "%02x", $0) }.joined()
    }
}
