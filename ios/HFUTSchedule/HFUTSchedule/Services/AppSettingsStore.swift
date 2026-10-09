import Foundation
import Security

/// 设置项统一存放的 Key（对应上游 DataStoreManager 的各个偏好）。
enum AppSettingsKey {
    static let appearance = "appAppearanceMode"          // 深浅色：auto/light/dark
    static let pureBlack = "appPureBlackBackground"      // 纯黑深色背景
    static let webDarkMode = "appForceWebDarkMode"       // 强制网页深色模式
    static let accentHex = "appAccentColorHex"           // 主题色
    static let accentSaturation = "appAccentSaturation"  // 鲜艳度
    static let liquidGlass = "appLiquidGlassEnabled"     // 液态玻璃
    static let showTeacherInSquare = "timetableShowsTeacher"   // 方格内显示教师
    static let mergeConflictingSquares = "timetableMergesConflicts" // 合并冲突方格
    static let backgroundBlur = "timetableBackgroundBlur"      // 课表前景模糊
    static let timetableBackground = "timetableBackgroundData" // 课表背景图（文件名）
    static let showAllTabLabels = "appShowsAllTabLabels"       // 显示所有底栏标签
    static let showFinishedToday = "focusShowsFinishedToday"   // 聚焦仍显示今天已完成
    static let showExpiredEvents = "focusShowsExpiredEvents"   // 聚焦显示已结束日程
    static let xuanchengQuota = "xuanchengNetworkQuotaGiB"    // 宣城校园网月额度
    static let autoRefreshLogin = "appAutoRefreshLogin"        // 自动刷新登录状态
    static let dataReporting = "appAllowsDataReporting"        // 数据上报
    static let pageSize = "appRequestPageSize"                 // 请求范围
    static let defaultCourseSource = "defaultCourseSource"     // 默认课程表
    static let autoTermStart = "appAutoTermStart"              // 自动计算学期
    static let manualTermStart = "appManualTermStart"          // 学期开始时间
    static let useDefaultCardPassword = "useDefaultCardPassword" // 使用默认一卡通密码
    static let ignoreExcludedGrades = "ignoreUnjoinedGradeItems" // 忽略平均成绩的排除计算
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case auto, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }
}

enum DefaultCourseSource: String, CaseIterable, Identifiable {
    case academic, community
    var id: String { rawValue }
    var title: String {
        switch self {
        case .academic: "合工大教务"
        case .community: "智慧社区"
        }
    }
    var detail: String {
        switch self {
        case .academic: "合工大教务数据源的课程表会自动刷新，最优推荐"
        case .community: "智慧社区课表有时会不更新数据，且不支持调休"
        }
    }
}

/// 敏感设置项（一卡通密码、校园网密码、教务密码、大模型 Key）使用钥匙串保存。
enum AppSecretStore {
    private static let service = "com.xiaozhangwangxue.hfutschedule.settings"

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            SecItemDelete(query as CFDictionary)
            return
        }
        let attributes: [String: Any] = [kSecValueData as String: Data(trimmed.utf8)]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = Data(trimmed.utf8)
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    enum Account {
        static let cardPassword = "card-password"
        static let schoolNetPassword = "school-net-password"
        static let academicPassword = "academic-password"
        static let aiAPIKey = "ai-api-key"
    }

    /// 证件号后 6 位（末位为 X 时取 X 前 6 位），对应上游默认一卡通/校园网密码规则。
    static func defaultPassword(fromIdentity identity: String?) -> String? {
        guard let identity, identity.count >= 7 else { return nil }
        let tail = String(identity.suffix(7))
        if tail.uppercased().hasSuffix("X") {
            return String(tail.prefix(6))
        }
        return String(tail.suffix(6))
    }
}
