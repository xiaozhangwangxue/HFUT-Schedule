import Foundation
import Security

/// 主应用与小组件之间的数据通道。
///
/// 免费个人团队不能使用 App Groups，所以这里使用三条通道按优先级读取：
/// 1. App Group（签名支持时自动生效）
/// 2. 共享钥匙串（免费团队描述文件自带 `TEAM.*` keychain 分组，可用）
/// 3. 构建时写入小组件包内的快照 JSON（保底，保证小组件永远有内容显示）
enum WidgetScheduleBridge {
    static let widgetKind = "HFUTWeeklyScheduleWidget"
    static let appGroupIdentifier = "group.com.xiaozhangwangxue.hfutschedule.ios"
    static let snapshotDefaultsKey = "weeklyScheduleSnapshotV1"
    static let bundledSnapshotResource = "ScheduleSnapshot"
    static let documentsSnapshotName = "hfut-widget-snapshot.json"
    static let keychainService = "com.xiaozhangwangxue.hfutschedule.widget.snapshot"
    static let keychainAccount = "weekly-schedule"
    static let keychainAccessGroup = "K6T9P3LS8V.com.xiaozhangwangxue.hfutschedule.ios"
}

struct WidgetCourseSnapshot: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var teacher: String
    var location: String
    var weekday: Int
    var startTime: String
    var endTime: String
    var colorIndex: Int
    var weekIndices: [Int]?
    var dates: [String]?
}

enum WidgetSnapshotStore {
    static func encode(_ courses: [WidgetCourseSnapshot]) -> Data? {
        try? JSONEncoder().encode(courses)
    }

    static func decode(_ data: Data) -> [WidgetCourseSnapshot] {
        (try? JSONDecoder().decode([WidgetCourseSnapshot].self, from: data)) ?? []
    }

    /// 主应用在课表变化时调用：写入所有可用通道，并留一份 Documents 副本便于导出。
    static func store(_ courses: [WidgetCourseSnapshot]) {
        guard let data = encode(courses) else { return }
        if let defaults = UserDefaults(suiteName: WidgetScheduleBridge.appGroupIdentifier) {
            defaults.set(data, forKey: WidgetScheduleBridge.snapshotDefaultsKey)
        }
        SharedKeychainSnapshot.write(data)
        writeDocumentsCopy(data)
    }

    /// 小组件读取：按可用性依次回退。
    static func load() -> [WidgetCourseSnapshot] {
        if let defaults = UserDefaults(suiteName: WidgetScheduleBridge.appGroupIdentifier),
           let data = defaults.data(forKey: WidgetScheduleBridge.snapshotDefaultsKey) {
            let courses = decode(data)
            if !courses.isEmpty { return courses }
        }
        if let data = SharedKeychainSnapshot.read() {
            let courses = decode(data)
            if !courses.isEmpty { return courses }
        }
        if let url = Bundle.main.url(
            forResource: WidgetScheduleBridge.bundledSnapshotResource,
            withExtension: "json"
        ), let data = try? Data(contentsOf: url) {
            return decode(data)
        }
        return []
    }

    private static func writeDocumentsCopy(_ data: Data) {
        guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let url = directory.appendingPathComponent(WidgetScheduleBridge.documentsSnapshotName)
        try? data.write(to: url, options: .atomic)
    }
}

private enum SharedKeychainSnapshot {
    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: WidgetScheduleBridge.keychainService,
            kSecAttrAccount as String: WidgetScheduleBridge.keychainAccount,
            kSecAttrAccessGroup as String: WidgetScheduleBridge.keychainAccessGroup
        ]
    }

    static func write(_ data: Data) {
        let query = baseQuery
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        guard status == errSecItemNotFound else { return }
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(insert as CFDictionary, nil)
    }

    static func read() -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
}
