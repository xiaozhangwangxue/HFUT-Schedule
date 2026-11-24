import SwiftUI
import UniformTypeIdentifiers

struct ScheduleBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .zip] }

    var payload: ScheduleBackupPayload
    var courses: [Course] { payload.courses }

    @MainActor init(courses: [Course], events: [CustomEvent] = []) {
        payload = ScheduleBackupPayload(courses: courses, events: events, preferences: BackupPreferences.capture(), applicationData: BackupApplicationData.capture())
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        payload = try ScheduleBackupPayload.decode(data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return FileWrapper(regularFileWithContents: try encoder.encode(payload))
    }
}
