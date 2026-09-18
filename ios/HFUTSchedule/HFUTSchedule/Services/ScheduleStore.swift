import Foundation
import WidgetKit

@MainActor
final class ScheduleStore: ObservableObject {
    @Published private(set) var courses: [Course] = []

    private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("HFUTSchedule", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("courses.json")
        load()
        removeLegacyPreviewDataIfNeeded()
        syncWidgetSnapshot()
    }

    func courses(on weekday: Int) -> [Course] {
        courses
            .filter { $0.weekday == weekday }
            .sorted { $0.startTime < $1.startTime }
    }

    func add(_ course: Course) {
        courses.append(course)
        save()
    }

    func remove(id: UUID) {
        courses.removeAll { $0.id == id }
        save()
    }

    func replace(with importedCourses: [Course]) {
        courses = importedCourses
        save()
    }

    func replaceAcademicCourses(with syncedCourses: [Course]) {
        let localCourses = courses.filter { $0.source != "academic" }
        courses = localCourses + syncedCourses
        save()
    }

    func removeAll() {
        courses.removeAll()
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Course].self, from: data) else { return }
        courses = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(courses) else { return }
        try? data.write(to: fileURL, options: .atomic)
        syncWidgetSnapshot()
    }

    private func syncWidgetSnapshot() {
        WidgetSnapshotStore.store(courses.map(WidgetCourseSnapshot.init))
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetScheduleBridge.widgetKind)
    }

    private func removeLegacyPreviewDataIfNeeded() {
        let migrationKey = "removedLegacyPreviewScheduleV1"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: migrationKey) }

        let previewSignatures = Set(Course.preview.map(Self.signature))
        let storedSignatures = Set(courses.map(Self.signature))
        guard !courses.isEmpty,
              courses.allSatisfy({ $0.source == nil }),
              storedSignatures.isSubset(of: previewSignatures) else { return }
        courses.removeAll()
        save()
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
