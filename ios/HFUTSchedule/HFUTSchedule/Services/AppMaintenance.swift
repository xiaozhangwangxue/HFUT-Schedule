import Foundation
import UIKit
import WebKit

struct AppRelease: Decodable, Identifiable, Equatable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: URL
    let publishedAt: String?
    let draft: Bool
    let prerelease: Bool
    var id: String { tagName }
    var version: String { String(tagName.dropFirst("ios-v".count)) }
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name", htmlURL = "html_url", publishedAt = "published_at"
        case name, body, draft, prerelease
    }
}

struct AppReleaseClient {
    let session: URLSession
    init(session: URLSession = .shared) { self.session = session }
    func releases() async throws -> [AppRelease] {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/xiaozhangwangxue/HFUT-Schedule/releases?per_page=100")!)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("HFUTSchedule-iOS", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode), data.count < 4_194_304 else {
            throw MaintenanceError.versionRequestFailed
        }
        return try Self.decode(data)
    }
    static func decode(_ data: Data) throws -> [AppRelease] {
        let releases = try JSONDecoder().decode([AppRelease].self, from: data)
            .filter { !$0.draft && !$0.prerelease && $0.tagName.hasPrefix("ios-v") && numericVersion($0.version) != nil }
            .sorted { compare($0.version, $1.version) == .orderedDescending }
        guard !releases.isEmpty else { throw MaintenanceError.noIOSRelease }
        return releases
    }
    static func numericVersion(_ value: String) -> [Int]? {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...4).contains(parts.count) else { return nil }
        let numbers = parts.compactMap { Int($0) }
        return numbers.count == parts.count && numbers.allSatisfy({ $0 >= 0 }) ? numbers : nil
    }
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let a = numericVersion(lhs) ?? [], b = numericVersion(rhs) ?? []
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}

enum MaintenanceError: LocalizedError {
    case versionRequestFailed, noIOSRelease
    var errorDescription: String? {
        switch self {
        case .versionRequestFailed: "版本服务器未返回有效结果，请稍后重试"
        case .noIOSRelease: "没有找到可核实的 iOS 正式版本"
        }
    }
}

@MainActor
enum AppDiagnostics {
    static func report(now: Date = Date()) -> String {
        let bundle = Bundle.main
        let available = (try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        let values = [
            "聚在工大 iOS 诊断", "生成时间：\(now.formatted(.iso8601))",
            "版本：\(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "未知") (\(bundle.object(forInfoDictionaryKey: "CFBundleVersion") ?? "未知"))",
            "系统：\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            "设备类型：\(UIDevice.current.model)",
            "屏幕：\(Int(UIScreen.main.bounds.width)) × \(Int(UIScreen.main.bounds.height)) @\(UIScreen.main.scale)x",
            "磁盘可用：\(ByteCountFormatter.string(fromByteCount: available, countStyle: .file))",
            "WebVPN 转换：\(WebVPNBrowsingSession.shared.isEnabled ? "开启" : "关闭")",
            "访问方式：\(UserDefaults.standard.string(forKey: "academicConnectionMode") ?? "direct")",
            "课表来源：\(UserDefaults.standard.string(forKey: AppSettingsKey.defaultCourseSource) ?? "academic")",
            "本地OCR模型：\(CaptchaModelStore.statusText)",
            "提示：此报告不包含账号、课表正文、Cookie、密码、API Key 或令牌。"
        ]
        return values.joined(separator: "\n")
    }
}

@MainActor
enum AppCacheManager {
    static func sizeText() -> String {
        let total = cachesURL.map { directorySize($0) } ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(total + URLCache.shared.currentMemoryUsage), countStyle: .file)
    }
    private static var cachesURL: URL? { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first }
    private static func directorySize(_ url: URL) -> Int {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else { return 0 }
        return files.compactMap { $0 as? URL }.reduce(0) { size, url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return size + (values?.isRegularFile == true ? values?.fileSize ?? 0 : 0)
        }
    }
    static func clear() async throws {
        URLCache.shared.removeAllCachedResponses()
        let types: Set<String> = [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeOfflineWebApplicationCache]
        await WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast)
        if let cachesURL {
            for item in try FileManager.default.contentsOfDirectory(at: cachesURL, includingPropertiesForKeys: nil) {
                try FileManager.default.removeItem(at: item)
            }
        }
    }
}
