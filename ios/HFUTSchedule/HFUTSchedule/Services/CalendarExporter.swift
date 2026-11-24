import EventKit
import Foundation

enum CalendarExportError: LocalizedError {
    case permissionDenied, calendarUnavailable, noActualDates
    var errorDescription: String? {
        switch self {
        case .permissionDenied: "没有日历读写权限，请在系统设置中允许访问日历。"
        case .calendarUnavailable: "未找到所选的可写入系统日历，请重新选择。"
        case .noActualDates: "没有可导出的实际日期。请先同步课程日期，或设置学期开始日。"
        }
    }
}

struct CalendarAccountOption: Identifiable, Equatable {
    let id: String
    let title: String
    let account: String
}

@MainActor
final class CalendarExporter {
    static let selectedCalendarKey = "platformExportCalendarID"
    private static let ledgerKey = "platformCalendarExports.v1"
    private static let marker = "由聚在工大 iOS 添加 [HFUTSchedule]"
    private let store: EKEventStore
    private let defaults: UserDefaults

    init(store: EKEventStore = EKEventStore(), defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
    }

    func calendars() async throws -> [CalendarAccountOption] {
        try await authorize()
        return store.calendars(for: .event).filter(\.allowsContentModifications).map {
            CalendarAccountOption(id: $0.calendarIdentifier, title: $0.title, account: $0.source.title)
        }.sorted { $0.account == $1.account ? $0.title < $1.title : $0.account < $1.account }
    }

    func export(_ courses: [Course]) async throws -> Int {
        let occurrences = PlatformScheduleResolver.occurrences(courses: courses, termStart: ScheduleCalendar.termStart(from: courses))
        return try await export(occurrences, calendarID: defaults.string(forKey: Self.selectedCalendarKey))
    }

    @discardableResult
    func export(_ occurrences: [PlatformScheduleOccurrence], calendarID: String? = nil,
                replacingPrevious: Bool = false) async throws -> Int {
        guard !occurrences.isEmpty else { throw CalendarExportError.noActualDates }
        try await authorize()
        let calendar = try targetCalendar(calendarID)
        let key = calendar.calendarIdentifier
        var ledger = savedLedger()
        var entries = ledger[key] ?? [:]
        var newEvents: [(String, EKEvent)] = []
        do {
            if replacingPrevious {
                try removeTracked(entries, calendarID: key)
                entries = [:]
            }
            for occurrence in occurrences {
                let existing = entries[occurrence.id].flatMap { store.event(withIdentifier: $0) }
                let event = existing.flatMap { isOurs($0) && $0.calendar.calendarIdentifier == key ? $0 : nil } ?? EKEvent(eventStore: store)
                event.title = occurrence.title
                event.location = occurrence.location
                event.notes = [Self.marker, occurrence.detail].filter { !$0.isEmpty }.joined(separator: "\n")
                event.startDate = occurrence.start
                event.endDate = occurrence.end
                event.calendar = calendar
                event.url = occurrence.routeURL
                event.alarms = [EKAlarm(relativeOffset: -15 * 60)]
                try store.save(event, span: .thisEvent, commit: false)
                newEvents.append((occurrence.id, event))
            }
            try store.commit()
        } catch {
            store.reset()
            throw error
        }
        for (identity, event) in newEvents {
            if let identifier = event.eventIdentifier { entries[identity] = identifier }
        }
        ledger[key] = entries
        defaults.set(ledger, forKey: Self.ledgerKey)
        defaults.set(key, forKey: Self.selectedCalendarKey)
        return newEvents.count
    }

    @discardableResult
    func clearExported(calendarID: String? = nil) async throws -> Int {
        try await authorize()
        let calendar = try targetCalendar(calendarID)
        var ledger = savedLedger()
        let entries = ledger[calendar.calendarIdentifier] ?? [:]
        do {
            let count = try removeTracked(entries, calendarID: calendar.calendarIdentifier)
            try store.commit()
            ledger.removeValue(forKey: calendar.calendarIdentifier)
            defaults.set(ledger, forKey: Self.ledgerKey)
            return count
        } catch { store.reset(); throw error }
    }

    private func authorize() async throws {
        guard try await store.requestFullAccessToEvents() else { throw CalendarExportError.permissionDenied }
    }

    private func targetCalendar(_ id: String?) throws -> EKCalendar {
        let target: EKCalendar?
        if let id, !id.isEmpty { target = store.calendar(withIdentifier: id) }
        else { target = store.defaultCalendarForNewEvents }
        guard let target, target.allowsContentModifications else { throw CalendarExportError.calendarUnavailable }
        return target
    }

    private func savedLedger() -> [String: [String: String]] {
        defaults.dictionary(forKey: Self.ledgerKey) as? [String: [String: String]] ?? [:]
    }

    private func isOurs(_ event: EKEvent) -> Bool { event.notes?.contains(Self.marker) == true }

    @discardableResult
    private func removeTracked(_ entries: [String: String], calendarID: String) throws -> Int {
        var count = 0
        for identifier in Set(entries.values) {
            guard let event = store.event(withIdentifier: identifier), isOurs(event), event.calendar.calendarIdentifier == calendarID else { continue }
            try store.remove(event, span: .thisEvent, commit: false)
            count += 1
        }
        return count
    }
}
