import Foundation

/// iOS 备份只包含课表、日程和可移植偏好；账号、Cookie、密码、API Key 均不导出。
struct ScheduleBackupPayload: Codable {
    var formatVersion: Int = 2
    var courses: [Course]
    var events: [CustomEvent]?
    var preferences: [String: BackupPreference]?

    static func decode(_ data: Data) throws -> Self {
        let decoder = JSONDecoder()
        if let legacy = try? decoder.decode([Course].self, from: data) {
            return Self(courses: legacy, events: nil, preferences: nil)
        }
        let result = try decoder.decode(Self.self, from: data)
        guard result.formatVersion == 2, result.events?.allSatisfy(\.isValid) != false else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return result
    }
}

enum BackupPreference: Codable, Equatable {
    case bool(Bool), number(Double), string(String)

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let bool = try? value.decode(Bool.self) { self = .bool(bool) }
        else if let number = try? value.decode(Double.self) { self = .number(number) }
        else { self = .string(try value.decode(String.self)) }
    }

    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .bool(let item): try value.encode(item)
        case .number(let item): try value.encode(item)
        case .string(let item): try value.encode(item)
        }
    }
}

enum BackupPreferences {
    static let booleans = [AppSettingsKey.pureBlack, AppSettingsKey.webDarkMode,
        AppSettingsKey.liquidGlass, AppSettingsKey.showTeacherInSquare,
        AppSettingsKey.mergeConflictingSquares, AppSettingsKey.showAllTabLabels,
        AppSettingsKey.showFinishedToday, AppSettingsKey.showExpiredEvents,
        AppSettingsKey.autoTermStart, AppSettingsKey.ignoreExcludedGrades, "scheduleShowsWeekend"]
    static let choices: [String: [String]] = [
        AppSettingsKey.appearance: ["auto", "light", "dark"],
        AppSettingsKey.defaultCourseSource: ["academic", "community"]
    ]
    static let ranges: [String: ClosedRange<Double>] = [
        AppSettingsKey.accentSaturation: 0...2,
        AppSettingsKey.backgroundBlur: 0...1,
        AppSettingsKey.manualTermStart: 0...4_102_444_800,
        AppSettingsKey.xuanchengQuota: 5...100,
        AppSettingsKey.pageSize: 10...100,
        AppSettingsKey.focusCardAction: 0...2
    ]

    static func capture(from defaults: UserDefaults = .standard) -> [String: BackupPreference] {
        var values: [String: BackupPreference] = [
            AppSettingsKey.appearance: .string("auto"), AppSettingsKey.defaultCourseSource: .string("academic"),
            AppSettingsKey.accentHex: .string(""), AppSettingsKey.accentSaturation: .number(1),
            AppSettingsKey.backgroundBlur: .number(0.35), AppSettingsKey.manualTermStart: .number(0),
            AppSettingsKey.xuanchengQuota: .number(30), AppSettingsKey.pageSize: .number(30),
            AppSettingsKey.focusCardAction: .number(1)
        ]
        for key in booleans { values[key] = .bool([AppSettingsKey.liquidGlass, AppSettingsKey.showAllTabLabels,
            AppSettingsKey.showFinishedToday, AppSettingsKey.autoTermStart].contains(key)) }
        for key in booleans where defaults.object(forKey: key) != nil { values[key] = .bool(defaults.bool(forKey: key)) }
        for key in choices.keys where defaults.string(forKey: key) != nil { values[key] = .string(defaults.string(forKey: key)!) }
        for key in ranges.keys where defaults.object(forKey: key) != nil { values[key] = .number(defaults.double(forKey: key)) }
        if let hex = defaults.string(forKey: AppSettingsKey.accentHex) { values[AppSettingsKey.accentHex] = .string(hex) }
        return normalized(values)
    }

    static func normalized(_ values: [String: BackupPreference]) -> [String: BackupPreference] {
        var result: [String: BackupPreference] = [:]
        for (key, value) in values {
            switch value {
            case .bool where booleans.contains(key): result[key] = value
            case .string(let string) where choices[key]?.contains(string) == true: result[key] = value
            case .string(let string) where key == AppSettingsKey.accentHex:
                if string.isEmpty || string.range(of: "^[0-9a-fA-F]{6}$", options: .regularExpression) != nil { result[key] = value }
            case .number(let number):
                guard let range = ranges[key], number.isFinite else { continue }
                var normalized = min(range.upperBound, max(range.lowerBound, number))
                if key == AppSettingsKey.focusCardAction || key == AppSettingsKey.pageSize { normalized = normalized.rounded(.down) }
                result[key] = .number(normalized)
            default: break // 未知平台或未知系统版本的开关不进入本机设置。
            }
        }
        return result
    }

    static func restore(_ values: [String: BackupPreference], to defaults: UserDefaults = .standard) {
        for (key, value) in normalized(values) {
            switch value {
            case .bool(let item): defaults.set(item, forKey: key)
            case .number(let item): defaults.set(item, forKey: key)
            case .string(let item): defaults.set(item, forKey: key)
            }
        }
    }
}
