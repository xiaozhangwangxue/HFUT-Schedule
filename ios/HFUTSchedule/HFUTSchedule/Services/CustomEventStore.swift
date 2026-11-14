import Foundation
import Combine

@MainActor
final class CustomEventStore: ObservableObject {
    @Published private(set) var events: [CustomEvent] = []
    @Published private(set) var storageError: String?
    @Published private(set) var requiresRecovery = false
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HFUTSchedule", isDirectory: true)
        self.fileURL = fileURL ?? directory.appendingPathComponent("custom-events.json")
        guard FileManager.default.fileExists(atPath: self.fileURL.path) else { return }
        do {
            let decoded = try JSONDecoder().decode([CustomEvent].self, from: Data(contentsOf: self.fileURL))
            guard Self.isValid(decoded) else { throw CocoaError(.fileReadCorruptFile) }
            events = decoded
        } catch {
            // 保留原文件，阻止保存覆盖：损坏数据不能让整个应用崩溃，也不能被空数据抹掉。
            storageError = "日程读取失败，原文件已保留。请先从备份恢复。"
            requiresRecovery = true
        }
    }

    @discardableResult
    func save(_ event: CustomEvent) -> Bool {
        guard !requiresRecovery else { return false }
        guard event.isValid else { storageError = "日程标题或时间无效。"; return false }
        var next = events
        if let index = next.firstIndex(where: { $0.id == event.id }) { next[index] = event }
        else { next.append(event) }
        return persist(next)
    }

    @discardableResult
    func remove(_ id: UUID) -> Bool {
        guard !requiresRecovery else { return false }
        return persist(events.filter { $0.id != id })
    }

    @discardableResult
    func restore(_ restored: [CustomEvent]) -> Bool {
        guard Self.isValid(restored) else {
            storageError = "日程备份含有无效或重复的数据，恢复已停止。"
            return false
        }
        // 显式恢复前保留损坏的原文件，便于找回。
        if requiresRecovery, FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                try FileManager.default.copyItem(at: fileURL, to: fileURL.deletingPathExtension()
                    .appendingPathExtension("recovery-\(UUID().uuidString).json"))
            } catch { storageError = "无法保留原日程文件，恢复已停止。"; return false }
        }
        return persist(restored)
    }

    private static func isValid(_ events: [CustomEvent]) -> Bool {
        events.allSatisfy(\.isValid) && Set(events.map(\.id)).count == events.count
    }

    private func persist(_ next: [CustomEvent]) -> Bool {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: fileURL, options: .atomic)
            events = next
            storageError = nil
            requiresRecovery = false
            return true
        } catch {
            storageError = "日程保存失败，请检查设备存储后重试。"
            return false
        }
    }
}
