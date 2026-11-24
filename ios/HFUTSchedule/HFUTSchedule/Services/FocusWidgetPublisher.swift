import Foundation
import WidgetKit

@MainActor
enum FocusWidgetPublisher {
    static let fontScaleKey = "focusWidgetFontScale"
    static let tomorrowKey = "focusWidgetSwitchesToTomorrow"

    @discardableResult
    static func publish(schedule: ScheduleStore, exams: [AcademicExam], events: [CustomEvent], now: Date = Date()) -> Bool {
        let calendar = FocusPlanResolver.calendar
        var courses: [PlatformScheduleOccurrence] = []
        // Resolve holidays/make-up mappings through the same path as Focus.
        // The widget only needs today/tomorrow, retaining a 60-day offline window.
        for offset in -1...60 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) else { continue }
            let values = FocusPlanResolver.courses(on: day, store: schedule).map { course -> Course in
                var value = course
                value.dates = [HolidayCalendarStore.key(for: day)]
                return value
            }
            courses += PlatformScheduleResolver.occurrences(courses: values, termStart: nil, calendar: calendar)
        }
        let other = PlatformScheduleResolver.occurrences(courses: [], exams: exams, events: events, termStart: nil, calendar: calendar)
        let items = (courses + other).map { FocusWidgetItem(id: $0.id, title: $0.title, location: $0.location,
            start: $0.start, end: $0.end, kind: $0.kind.rawValue, route: $0.routeURL?.absoluteString ?? "hfut-schedule://home") }
        let defaults = UserDefaults.standard
        let font = defaults.object(forKey: fontScaleKey) as? Double ?? 1
        let snapshot = FocusWidgetSnapshot(revision: UUID(), updatedAt: now, items: items,
            fontScale: font.isFinite ? max(0.8, min(1.5, font)) : 1,
            showFinished: defaults.object(forKey: AppSettingsKey.showFinishedToday) as? Bool ?? true,
            switchesToTomorrow: defaults.object(forKey: tomorrowKey) as? Bool ?? true)
        let written = FocusWidgetSnapshotStore.store(snapshot)
        if written { WidgetCenter.shared.reloadTimelines(ofKind: FocusWidgetSnapshotStore.widgetKind) }
        return written
    }
}
