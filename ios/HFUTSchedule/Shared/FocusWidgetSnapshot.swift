import Foundation
import Security

struct FocusWidgetItem: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let location: String
    let start: Date
    let end: Date
    let kind: String
    let route: String
}

struct FocusWidgetSnapshot: Codable, Equatable {
    let revision: UUID
    let updatedAt: Date
    let items: [FocusWidgetItem]
    let fontScale: Double
    let showFinished: Bool
    let switchesToTomorrow: Bool
}

struct FocusWidgetDay: Equatable {
    let date: Date
    let isTomorrow: Bool
    let items: [FocusWidgetItem]
}

enum FocusWidgetProjection {
    static func day(_ snapshot: FocusWidgetSnapshot, now: Date, calendar source: Calendar = .current) -> FocusWidgetDay {
        let calendar = WidgetScheduleCalendar.gregorian(source)
        let today = snapshot.items.filter { appears($0, on: now, calendar: calendar) }
        // Exams/custom events remain on the appropriate day. Automatic course
        // switching follows the original final-lesson rule.
        let lastLesson = today.filter { $0.kind == "course" }.map(\.end).max()
        let pendingOther = today.contains { $0.kind != "course" && $0.end > now }
        let tomorrow = snapshot.switchesToTomorrow && !pendingOther && (lastLesson == nil || now >= lastLesson!)
        let day = tomorrow ? calendar.date(byAdding: .day, value: 1, to: now) ?? now : now
        let items = snapshot.items.filter {
            appears($0, on: day, calendar: calendar) && (tomorrow || snapshot.showFinished || $0.end > now)
        }.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
        return FocusWidgetDay(date: day, isTomorrow: tomorrow, items: items)
    }

    private static func appears(_ item: FocusWidgetItem, on day: Date, calendar: Calendar) -> Bool {
        if item.kind == "deadline" { return calendar.isDate(item.end, inSameDayAs: day) }
        let first = calendar.startOfDay(for: day)
        let next = calendar.date(byAdding: .day, value: 1, to: first) ?? first.addingTimeInterval(86_400)
        return item.start < next && item.end > first
    }

    static func refreshDates(_ snapshot: FocusWidgetSnapshot?, now: Date, calendar source: Calendar = .current) -> [Date] {
        let calendar = WidgetScheduleCalendar.gregorian(source)
        let boundary = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(172_800)
        let dates = (snapshot?.items ?? []).flatMap { [$0.start, $0.end] }.filter { $0 > now && $0 < boundary }
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
        return Array(Set([now, midnight] + dates)).sorted().prefix(100).map { $0 }
    }
}

/// Same dual transport as the weekly widget. A newly re-signed app/extension
/// still needs a common App Group or Keychain group; there is no silent bypass.
enum FocusWidgetSnapshotStore {
    static let widgetKind = "HFUTFocusScheduleWidget"
    private static let account = "focus-schedule.v1"
    private static let filename = "focus-schedule-v1.json"
    static func load() -> FocusWidgetSnapshot? {
        [groupURL().flatMap { try? Data(contentsOf: $0) }, keychainRead()].compactMap { $0 }
            .compactMap { try? JSONDecoder().decode(FocusWidgetSnapshot.self, from: $0) }
            .max { $0.updatedAt < $1.updatedAt }
    }
    @discardableResult static func store(_ snapshot: FocusWidgetSnapshot) -> Bool {
        guard let data = try? JSONEncoder().encode(snapshot) else { return false }
        var groupWritten = false
        if let url = groupURL() { do { try data.write(to: url, options: .atomic); groupWritten = true } catch {} }
        let query = keychainQuery()
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(insert as CFDictionary, nil)
        }
        return groupWritten || status == errSecSuccess
    }
    private static func groupURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetScheduleBridge.appGroupIdentifier)?.appendingPathComponent(filename)
    }
    private static func keychainQuery() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: WidgetScheduleBridge.keychainService,
         kSecAttrAccount as String: account]
    }
    private static func keychainRead() -> Data? {
        var query = keychainQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
}
