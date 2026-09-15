import Foundation

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
