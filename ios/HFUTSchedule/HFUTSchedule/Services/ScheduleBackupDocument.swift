import SwiftUI
import UniformTypeIdentifiers

struct ScheduleBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var courses: [Course]

    init(courses: [Course]) {
        self.courses = courses
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        courses = try JSONDecoder().decode([Course].self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return FileWrapper(regularFileWithContents: try encoder.encode(courses))
    }
}
