import Foundation

/// holiday-cn 数据源里的一天（原项目使用 Chiu-xaH/holiday-cn）。
struct HolidayDay: Codable, Equatable, Hashable {
    let name: String
    let date: String
    let isOffDay: Bool
}

/// 与 Android 版 Day.kt 对应的节假日 / 调休判断。
final class HolidayCalendarStore: @unchecked Sendable {
    static let shared = HolidayCalendarStore()

    private static let cacheKey = "holidayCalendarCacheV1"
    private static let endpoint = "https://raw.githubusercontent.com/Chiu-xaH/holiday-cn/master/"

    private(set) var days: [HolidayDay] = []
    private var lastLoaded: Date?
    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        session = URLSession(configuration: configuration)
        loadCache()
    }

    // MARK: - 查询

    func day(on date: Date) -> HolidayDay? {
        let key = Self.key(for: date)
        return days.first { $0.date == key }
    }

    func isOffDay(_ date: Date) -> Bool {
        day(on: date)?.isOffDay == true
    }

    /// 调休上班日（数据里 isOffDay = false，且落在节假日安排中）。
    func isMakeUpWorkDay(_ date: Date) -> Bool {
        guard let entry = day(on: date) else { return false }
        return !entry.isOffDay
    }

    func name(on date: Date) -> String? {
        day(on: date)?.name
    }

    // MARK: - 刷新

    func refreshIfNeeded(force: Bool = false) async {
        let now = Date()
        if !force, let lastLoaded, now.timeIntervalSince(lastLoaded) < 60 * 60 * 12 { return }
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: now)
        // 跨年时同时缓存下一年，避免元旦前后查不到安排。
        let years = Set([currentYear, currentYear + 1])
        var merged = days
        var updated = false
        for year in years.sorted() {
            guard let fetched = try? await fetch(year: year), !fetched.isEmpty else { continue }
            merged.removeAll { $0.date.hasPrefix("\(year)-") }
            merged.append(contentsOf: fetched)
            updated = true
        }
        guard updated else { return }
        days = merged.sorted { $0.date < $1.date }
        lastLoaded = Date()
        persistCache()
    }

    private func fetch(year: Int) async throws -> [HolidayDay] {
        guard let url = URL(string: "\(Self.endpoint)\(year).json") else { return [] }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["days"] as? [[String: Any]] else {
            throw URLError(.cannotParseResponse)
        }
        return list.compactMap { item in
            guard let name = item["name"] as? String,
                  let date = item["date"] as? String,
                  let isOffDay = item["isOffDay"] as? Bool else { return nil }
            return HolidayDay(name: name, date: date, isOffDay: isOffDay)
        }
    }

    private func persistCache() {
        guard let data = try? JSONEncoder().encode(days) else { return }
        UserDefaults.standard.set(data, forKey: Self.cacheKey)
    }

    private func loadCache() {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey),
              let cached = try? JSONDecoder().decode([HolidayDay].self, from: data) else { return }
        days = cached
    }

    static func key(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

/// 调休补课设置：originDate（调休当天）→ targetDate（按哪天课表上课）。
/// 对应 Android 版 Room 表 special_work_day。
final class SpecialWorkDayStore: @unchecked Sendable {
    static let shared = SpecialWorkDayStore()

    private static let key = "specialWorkDayMappingV1"
    private var mapping: [String: String] = [:]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            mapping = decoded
        }
    }

    func targetDate(for date: Date) -> String? {
        mapping[HolidayCalendarStore.key(for: date)]
    }

    func targetDate(forOriginKey key: String) -> String? {
        mapping[key]
    }

    func setTarget(_ targetDate: String, for date: Date) {
        mapping[HolidayCalendarStore.key(for: date)] = targetDate
        persist()
    }

    func removeTarget(for date: Date) {
        mapping.removeValue(forKey: HolidayCalendarStore.key(for: date))
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(mapping) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
