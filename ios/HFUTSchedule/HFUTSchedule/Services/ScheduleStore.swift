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

    func installPreviewData() {
        courses = Course.preview
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
}
