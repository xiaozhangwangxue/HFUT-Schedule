import Foundation
import Combine
import WidgetKit

@MainActor
final class ScheduleStore: ObservableObject {
    @Published private(set) var courses: [Course] = []
    @Published private(set) var storageError: String?
    @Published private(set) var requiresRecovery = false

    private let fileURL: URL
    private let syncWidgets: Bool

    init(fileURL: URL? = nil, syncWidgets: Bool = true) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("HFUTSchedule", isDirectory: true)
        self.fileURL = fileURL ?? directory.appendingPathComponent("courses.json")
        self.syncWidgets = syncWidgets
        load()
        // A failed/empty initial read must not overwrite a valid shared widget
        // snapshot. Publish a new snapshot only after a successful mutation.
        if fileURL == nil, !requiresRecovery { removeLegacyPreviewDataIfNeeded() }
    }

    func courses(on weekday: Int) -> [Course] {
        courses
            .filter { $0.weekday == weekday }
            .sorted { $0.startTime < $1.startTime }
    }

    @discardableResult
    func add(_ course: Course) -> Bool {
        guard !requiresRecovery else { return false }
        return persist(courses + [course])
    }

    @discardableResult
    func remove(id: UUID) -> Bool {
        guard !requiresRecovery else { return false }
        return persist(courses.filter { $0.id != id })
    }

    /// Explicit restore is the only write allowed after a failed read. Preserve
    /// the original bytes first so an unreadable file remains recoverable.
    @discardableResult
    func replace(with importedCourses: [Course]) -> Bool {
        guard preserveUnreadableFileIfNeeded() else { return false }
        return persist(importedCourses)
    }

    @discardableResult
    func replaceAcademicCourses(with syncedCourses: [Course]) -> Bool {
        guard !requiresRecovery else { return false }
        let localCourses = courses.filter { $0.source != "academic" }
        return persist(localCourses + syncedCourses)
    }

    @discardableResult
    func removeAll() -> Bool {
        guard !requiresRecovery else { return false }
        return persist([])
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            courses = try JSONDecoder().decode([Course].self, from: Data(contentsOf: fileURL))
        } catch {
            requiresRecovery = true
            storageError = "课表读取失败，原文件已保留。请先从备份恢复。"
        }
    }

    private func preserveUnreadableFileIfNeeded() -> Bool {
        guard requiresRecovery, FileManager.default.fileExists(atPath: fileURL.path) else { return true }
        do {
            try FileManager.default.copyItem(at: fileURL, to: fileURL.deletingPathExtension()
                .appendingPathExtension("recovery-\(UUID().uuidString).json"))
            return true
        } catch {
            storageError = "无法保留原课表文件，恢复已停止。"
            return false
        }
    }

    private func persist(_ next: [Course]) -> Bool {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: fileURL, options: .atomic)
            courses = next
            requiresRecovery = false
            storageError = nil
            if syncWidgets { syncWidgetSnapshot() }
            return true
        } catch {
            // A transient write failure is retryable. Do not publish data that
            // was not saved, and do not turn it into a corruption lock.
            storageError = "课表保存失败，请检查设备存储后重试。"
            return false
        }
    }

    private func syncWidgetSnapshot() {
        WidgetSnapshotStore.store(courses.map(WidgetCourseSnapshot.init))
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetScheduleBridge.widgetKind)
    }

    private func removeLegacyPreviewDataIfNeeded() {
        let migrationKey = "removedLegacyPreviewScheduleV1"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        let previewSignatures = Set(Course.preview.map(Self.signature))
        let storedSignatures = Set(courses.map(Self.signature))
        if !courses.isEmpty,
           courses.allSatisfy({ $0.source == nil }),
           storedSignatures.isSubset(of: previewSignatures),
           !persist([]) { return }
        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    private static func signature(_ course: Course) -> String {
        [course.name, course.teacher, course.location, String(course.weekday), course.startTime, course.endTime]
            .joined(separator: "|")
    }
}

private extension WidgetCourseSnapshot {
    init(course: Course) {
        self.init(
            id: course.id,
            name: course.name,
            teacher: course.teacher,
            location: course.location,
            weekday: course.weekday,
            startTime: course.startTime,
            endTime: course.endTime,
            colorIndex: course.colorIndex,
            weekIndices: course.weekIndices,
            dates: course.dates
        )
    }
}
