import Foundation

struct CampusCloudLab: Identifiable, Equatable, Codable {
    let title: String
    let info: String
    let type: String
    var id: String { title + "|" + info }
    var url: URL? { URL(string: info) }
}

struct CampusCloudNotification: Identifiable, Equatable, Codable {
    let id: Int
    let title: String
    let info: String
    let remark: String
    let urlString: String?
    var url: URL? { urlString.flatMap(URL.init(string:)) }
}

/// 原项目的云端配置（https://chiu-xah.github.io/）：校历链接、实验室网址、通知与学期起始日。
final class CampusCloudConfigStore: @unchecked Sendable {
    static let shared = CampusCloudConfigStore()

    private static let endpoint = URL(string: "https://chiu-xah.github.io/")!
    private static let cacheKey = "campusCloudConfigCacheV1"

    private(set) var calendarURLString: String = ""
    private(set) var laboratories: [CampusCloudLab] = []
    private(set) var notifications: [CampusCloudNotification] = []
    private(set) var termStartDate: String = ""

    private var lastLoaded: Date?
    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        session = URLSession(configuration: configuration)
        loadCache()
    }

    var calendarURL: URL? {
        guard !calendarURLString.isEmpty else { return nil }
        return URL(string: calendarURLString)
    }

    func refreshIfNeeded(force: Bool = false) async {
        if !force, let lastLoaded, Date().timeIntervalSince(lastLoaded) < 1800 { return }
        do {
            let (data, response) = try await session.data(from: Self.endpoint)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            apply(root)
            lastLoaded = Date()
            persist(root)
        } catch {
            // 保留缓存配置
        }
    }

    private func apply(_ root: [String: Any]) {
        calendarURLString = (root["SchoolCalendar"] as? String) ?? calendarURLString
        termStartDate = (root["startDay"] as? String) ?? termStartDate
        laboratories = (root["Labs"] as? [[String: Any]] ?? []).compactMap { item in
            guard let title = item["title"] as? String, let info = item["info"] as? String else { return nil }
            return CampusCloudLab(title: title, info: info, type: (item["type"] as? String) ?? "WEB")
        }
        notifications = (root["Notifications"] as? [[String: Any]] ?? []).compactMap { item in
            guard let id = item["id"] as? Int, let title = item["title"] as? String else { return nil }
            return CampusCloudNotification(
                id: id,
                title: title,
                info: (item["info"] as? String) ?? "",
                remark: (item["remark"] as? String) ?? "",
                urlString: item["url"] as? String
            )
        }
    }

    private func persist(_ root: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: root) else { return }
        UserDefaults.standard.set(data, forKey: Self.cacheKey)
    }

    private func loadCache() {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        apply(root)
    }
}
