import Foundation
import Vision
import ImageIO
import CoreML

enum ScannerImageRecognitionError: LocalizedError {
    case invalidImage
    case recognitionUnavailable(Error)
    var errorDescription: String? {
        switch self {
        case .invalidImage: "无法读取这张图片，请换一张清晰的图片。"
        case .recognitionUnavailable: "系统图片识别服务暂时不可用。请换图重试，或使用实时扫码；如果持续失败，请更新 iOS 后重试。"
        }
    }
}

struct ScannedWiFi: Equatable {
    let name: String
    let password: String
    static func parse(_ text: String) -> ScannedWiFi? {
        guard text.hasPrefix("WIFI:") else { return nil }
        var fields: [String: String] = [:]
        var current = "", escaped = false
        func consume() {
            if let split = current.firstIndex(of: ":") { fields[String(current[..<split])] = String(current[current.index(after: split)...]) }
            current = ""
        }
        for character in text.dropFirst(5) {
            if escaped { current.append(character); escaped = false }
            else if character == "\\" { escaped = true }
            else if character == ";" { consume() }
            else { current.append(character) }
        }
        consume()
        guard let name = fields["S"], !name.isEmpty else { return nil }
        return ScannedWiFi(name: name, password: fields["P"] ?? "")
    }
}

enum ScannerService {
    static func webURL(_ text: String) -> URL? {
        guard let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }
    static func casURL(_ text: String) -> URL? {
        guard let url = webURL(text), url.path == "/cas/app/scanQrCodeLogin",
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let uuid = parts.queryItems?.first(where: { $0.name == "uuid" })?.value,
              !uuid.isEmpty, uuid.count <= 200 else { return nil }
        return url
    }
    static func decodeImage(_ data: Data) async throws -> [String] {
        try await Task.detached(priority: .userInitiated) {
            try autoreleasepool {
                try Task.checkCancellation()
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
                else { throw ScannerImageRecognitionError.invalidImage }
                let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
                let orientation = CGImagePropertyOrientation(rawValue: (properties?[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1) ?? .up
                // Keep the source, decoded pixels, request and handler alive
                // until perform returns and its results have been copied.
                do {
                    let latest = try recognize(image, orientation: orientation, cpuFallback: false)
                    if !latest.isEmpty { return latest }
                } catch is CancellationError { throw CancellationError() }
                catch { /* The CPU revision below is a real second detector. */ }
                try Task.checkCancellation()
                do { return try recognize(image, orientation: orientation, cpuFallback: true) }
                catch { throw ScannerImageRecognitionError.recognitionUnavailable(error) }
            }
        }.value
    }

    private static func recognize(_ image: CGImage, orientation: CGImagePropertyOrientation, cpuFallback: Bool) throws -> [String] {
        let request = VNDetectBarcodesRequest()
        if cpuFallback {
            // iOS 27.2's revision 3 simulator path may fail inference or return
            // no observations for a valid QR. Revision 2 remains supported and
            // has a separate CPU implementation; do not fake or skip a result.
            request.revision = VNDetectBarcodesRequestRevision2
            for (stage, devices) in try request.supportedComputeStageDevices {
                if let cpu = devices.first(where: { if case .cpu = $0 { return true }; return false }) {
                    request.setComputeDevice(cpu, for: stage)
                }
            }
        }
        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
        return try withExtendedLifetime((image, request, handler)) {
            try handler.perform([request])
            var seen = Set<String>()
            return (request.results ?? []).compactMap(\.payloadStringValue).filter { seen.insert($0).inserted }
        }
    }
}

enum ZhiJianScannerError: LocalizedError {
    case loginRequired, loginFailed, invalidCode, scanFailed, confirmFailed, invalidResponse
    var errorDescription: String? {
        switch self {
        case .loginRequired: "请先登录指间工大扫码服务。该会话与教务课表会话独立。"
        case .loginFailed: "指间工大登录失败，请检查信息门户账号、密码及网络后重试。"
        case .invalidCode: "这不是有效的校方统一认证登录二维码。"
        case .scanFailed: "校方未接受扫码请求，二维码可能已过期。请刷新二维码后重试。"
        case .confirmFailed: "校方未确认登录，请刷新二维码后重试。"
        case .invalidResponse: "校方服务暂时无法使用，请稍后重试。"
        }
    }
}

/// Matches WeChatZhiJianService. The scanned authority is never trusted for an
/// authenticated request: both stages are pinned to the official wx host.
actor ZhiJianScannerClient {
    static let shared = ZhiJianScannerClient()
    private static let tokenAccount = "zhijian-wx-ticket"
    private let session: URLSession
    private let readToken: @Sendable () -> String?
    private let writeToken: @Sendable (String) -> Void
    init(session: URLSession? = nil,
         readToken: @escaping @Sendable () -> String? = { AppSecretStore.read("zhijian-wx-ticket") },
         writeToken: @escaping @Sendable (String) -> Void = { AppSecretStore.write($0, account: "zhijian-wx-ticket") }) {
        self.readToken = readToken
        self.writeToken = writeToken
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.ephemeral
            config.httpCookieStorage = .shared
            config.timeoutIntervalForRequest = 25
            self.session = URLSession(configuration: config, delegate: ZhiJianRedirectDelegate(), delegateQueue: nil)
        }
    }
    func hasToken() -> Bool { readToken()?.hasPrefix("Bearer ") == true }
    func logout() { writeToken("") }
    func authorizedData(path: String, query: [URLQueryItem] = []) async throws -> Data {
        guard ["/api/center/user/selectUserInfoForApp", "/api/center/userGroup/selectCrewDataByOrgIdForAPP"].contains(path) else {
            throw ZhiJianScannerError.invalidResponse
        }
        guard let token = readToken(), token.hasPrefix("Bearer ") else { throw ZhiJianScannerError.loginRequired }
        let root = try await get(path: path, query: query, token: token)
        guard success(root) else { throw ZhiJianScannerError.invalidResponse }
        return try JSONSerialization.data(withJSONObject: root)
    }
    func login(username: String, password: String) async throws {
        CampusSessionStore.shared.bootstrap()
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !password.isEmpty else { throw ZhiJianScannerError.loginFailed }
        let stamp = try CASLoginClient.encryptAES(String(Int(Date().timeIntervalSince1970 * 1_000)), key: "b1o2s3s4s5o6f7t8")
        let root = try await get(path: "/api/auth/bsauth/getTgtWx", query: [
            URLQueryItem(name: "username", value: username.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(name: "password", value: password)
        ], token: nil, stamp: stamp)
        guard success(root), let data = root["data"] as? [String: Any],
              let token = data["ticket"] as? String, token.hasPrefix("Bearer ") else { throw ZhiJianScannerError.loginFailed }
        writeToken(token)
        guard readToken() == token else { throw ZhiJianScannerError.loginFailed }
    }
    func confirm(_ scannedText: String) async throws {
        guard let url = ScannerService.casURL(scannedText),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let uuid = components.queryItems?.first(where: { $0.name == "uuid" })?.value else { throw ZhiJianScannerError.invalidCode }
        guard let token = readToken(), token.hasPrefix("Bearer ") else { throw ZhiJianScannerError.loginRequired }
        let scan = try await get(path: "/cas/app/scanQrCodeLogin", query: components.queryItems ?? [], token: token)
        guard success(scan) else { throw ZhiJianScannerError.scanFailed }
        let confirmation = try await get(path: "/cas/app/confirmLogin", query: [URLQueryItem(name: "uuid", value: uuid)], token: token)
        guard success(confirmation) else { throw ZhiJianScannerError.confirmFailed }
    }
    private func get(path: String, query: [URLQueryItem], token: String?, stamp: String? = nil) async throws -> [String: Any] {
        var parts = URLComponents(string: "https://wx.hfut.edu.cn")!
        parts.path = path
        parts.queryItems = query
        var request = URLRequest(url: parts.url!)
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue(stamp, forHTTPHeaderField: "x-stamp")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.url?.host == "wx.hfut.edu.cn" else { throw ZhiJianScannerError.invalidResponse }
        if http.statusCode == 401 || http.statusCode == 403 { logout(); throw ZhiJianScannerError.loginRequired }
        guard (200..<300).contains(http.statusCode), let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ZhiJianScannerError.invalidResponse
        }
        return root
    }
    private func success(_ root: [String: Any]) -> Bool {
        (root["msg"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "success"
    }
}

private final class ZhiJianRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme == "https" && request.url?.host == "wx.hfut.edu.cn" ? request : nil)
    }
}
