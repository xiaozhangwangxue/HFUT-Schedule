import Foundation
import Security

/// App and extension must be re-signed with a common keychain access group.
/// Runtime queries use the groups granted by that signature, never a fixed team ID.
enum WidgetScheduleBridge {
    static let widgetKind = "HFUTWeeklyScheduleWidget"
    static let appGroupIdentifier = "group.com.xiaozhangwangxue.hfutschedule.ios"
    static let bundledSnapshotResource = "ScheduleSnapshot"
    static let documentsSnapshotName = "hfut-widget-snapshot.json"
    static let keychainService = "com.xiaozhangwangxue.hfutschedule.widget.snapshot"
    static let keychainAccount = "weekly-schedule"
    static let receiptAccount = "weekly-schedule.receipt"
    static let publicationStatusKey = "widgetPublicationStatusV2"
}

struct WidgetCourseSnapshot: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var teacher: String
    var location: String
    var weekday: Int
    var startTime: String
    var endTime: String
    var colorIndex: Int
    var weekIndices: [Int]?
    var dates: [String]?
}

struct WidgetScheduleSnapshot: Codable, Equatable {
    var formatVersion = 2
    var revision: UUID
    var updatedAt: Date
    var termStart: Date?
    var courses: [WidgetCourseSnapshot]
}

struct WidgetSnapshotReceipt: Codable, Equatable {
    let revision: UUID
    let readAt: Date
}

enum WidgetSnapshotSource: Equatable { case appGroup, keychain, bundle }

struct WidgetSnapshotLoadResult {
    let snapshot: WidgetScheduleSnapshot?
    let source: WidgetSnapshotSource?
    var hasScheduleData: Bool {
        guard let snapshot else { return false }
        return source != .bundle || !snapshot.courses.isEmpty
    }
}

struct WidgetPublicationStatus: Codable, Equatable {
    let revision: UUID
    let publishedAt: Date
    let courseCount: Int
    let appGroupWritten: Bool
    let keychainStatus: Int32

    var didWrite: Bool { appGroupWritten || keychainStatus == errSecSuccess }
}

/// All transport is injectable so tests never access a person's keychain or schedule.
struct WidgetSnapshotTransport {
    var readAppGroup: () -> Data?
    var writeAppGroup: (Data) -> Bool
    var readKeychain: () -> Data?
    var writeKeychain: (Data) -> Int32
    var readBundle: () -> Data?
    var readReceipt: () -> Data?
    var writeReceipt: (Data) -> Void
    var recordPublication: (WidgetPublicationStatus) -> Void
    var writeDocumentsCopy: (Data) -> Void

    static var live: Self {
        Self(
            readAppGroup: { SharedWidgetFiles.read("snapshot-v2.json") },
            writeAppGroup: { SharedWidgetFiles.write($0, name: "snapshot-v2.json") },
            readKeychain: { SharedKeychainSnapshot.read(account: WidgetScheduleBridge.keychainAccount) },
            writeKeychain: { SharedKeychainSnapshot.write($0, account: WidgetScheduleBridge.keychainAccount) },
            readBundle: {
                guard let url = Bundle.main.url(forResource: WidgetScheduleBridge.bundledSnapshotResource, withExtension: "json") else { return nil }
                return try? Data(contentsOf: url)
            },
            readReceipt: {
                let values = [SharedWidgetFiles.read("receipt-v2.json"), SharedKeychainSnapshot.read(account: WidgetScheduleBridge.receiptAccount)]
                return values.compactMap { $0 }.compactMap { data -> (Data, WidgetSnapshotReceipt)? in
                    guard let receipt = try? JSONDecoder().decode(WidgetSnapshotReceipt.self, from: data) else { return nil }
                    return (data, receipt)
                }.max(by: { $0.1.readAt < $1.1.readAt })?.0
            },
            writeReceipt: { data in
                _ = SharedWidgetFiles.write(data, name: "receipt-v2.json")
                _ = SharedKeychainSnapshot.write(data, account: WidgetScheduleBridge.receiptAccount)
            },
            recordPublication: { status in
                if let data = try? JSONEncoder().encode(status) { UserDefaults.standard.set(data, forKey: WidgetScheduleBridge.publicationStatusKey) }
            },
            writeDocumentsCopy: { data in
                guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try? data.write(to: directory.appendingPathComponent(WidgetScheduleBridge.documentsSnapshotName), options: .atomic)
            }
        )
    }
}

enum WidgetSnapshotStore {
    static func encode(_ courses: [WidgetCourseSnapshot]) -> Data? { try? JSONEncoder().encode(courses) }
    static func decode(_ data: Data) -> [WidgetCourseSnapshot] { decodeSnapshot(data)?.courses ?? [] }

    static func decodeSnapshot(_ data: Data) -> WidgetScheduleSnapshot? {
        if let snapshot = try? JSONDecoder().decode(WidgetScheduleSnapshot.self, from: data), snapshot.formatVersion == 2 {
            return snapshot
        }
        // Preserve compatibility with existing local and bundled array snapshots.
        guard let courses = try? JSONDecoder().decode([WidgetCourseSnapshot].self, from: data) else { return nil }
        return WidgetScheduleSnapshot(formatVersion: 1, revision: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
                                      updatedAt: .distantPast, termStart: nil, courses: courses)
    }

    @discardableResult
    static func store(_ courses: [WidgetCourseSnapshot], termStart: Date? = nil,
                      transport: WidgetSnapshotTransport = .live, now: Date = .now) -> Bool {
        let previous = loadSnapshot(transport: transport)
        let sameContent = previous?.formatVersion == 2 && previous?.courses == courses && previous?.termStart == termStart
        let revision = sameContent ? previous!.revision : UUID()
        let publicationDate = orderedDate(now: now, after: previous?.updatedAt)
        let snapshot = WidgetScheduleSnapshot(revision: revision, updatedAt: publicationDate, termStart: termStart, courses: courses)
        guard let data = try? JSONEncoder().encode(snapshot) else { return false }
        let groupWritten = transport.writeAppGroup(data)
        let keychainStatus = transport.writeKeychain(data)
        let status = WidgetPublicationStatus(revision: snapshot.revision, publishedAt: now,
            courseCount: courses.count, appGroupWritten: groupWritten, keychainStatus: keychainStatus)
        transport.recordPublication(status)
        transport.writeDocumentsCopy(data)
        return status.didWrite
    }

    static var lastSyncStatus: WidgetPublicationStatus? {
        guard let data = UserDefaults.standard.data(forKey: WidgetScheduleBridge.publicationStatusKey) else { return nil }
        return try? JSONDecoder().decode(WidgetPublicationStatus.self, from: data)
    }

    static func acknowledged(_ status: WidgetPublicationStatus, transport: WidgetSnapshotTransport = .live) -> Bool {
        guard let data = transport.readReceipt(), let receipt = try? JSONDecoder().decode(WidgetSnapshotReceipt.self, from: data) else { return false }
        return receipt.revision == status.revision
    }

    static func load() -> [WidgetCourseSnapshot] { loadSnapshot()?.courses ?? [] }

    static func loadSnapshot(acknowledge: Bool = false, transport: WidgetSnapshotTransport = .live) -> WidgetScheduleSnapshot? {
        loadResult(acknowledge: acknowledge, transport: transport).snapshot
    }

    static func loadResult(acknowledge: Bool = false, transport: WidgetSnapshotTransport = .live) -> WidgetSnapshotLoadResult {
        // A valid empty snapshot is authoritative. Never resurrect an older bundled schedule.
        let shared: [(WidgetScheduleSnapshot, WidgetSnapshotSource)] = [
            transport.readAppGroup().flatMap(decodeSnapshot).map { ($0, .appGroup) },
            transport.readKeychain().flatMap(decodeSnapshot).map { ($0, .keychain) }
        ].compactMap { $0 }
        if let newest = shared.max(by: { $0.0.updatedAt < $1.0.updatedAt }) {
            let previousReceipt = transport.readReceipt().flatMap { try? JSONDecoder().decode(WidgetSnapshotReceipt.self, from: $0) }
            let receiptDate = orderedDate(now: .now, after: previousReceipt?.readAt)
            if acknowledge, let receipt = try? JSONEncoder().encode(WidgetSnapshotReceipt(revision: newest.0.revision, readAt: receiptDate)) {
                transport.writeReceipt(receipt)
            }
            return WidgetSnapshotLoadResult(snapshot: newest.0, source: newest.1)
        }
        if let bundled = transport.readBundle().flatMap(decodeSnapshot) {
            return WidgetSnapshotLoadResult(snapshot: bundled, source: .bundle)
        }
        return WidgetSnapshotLoadResult(snapshot: nil, source: nil)
    }

    private static func orderedDate(now: Date, after previous: Date?) -> Date {
        guard let previous, previous >= now else { return now }
        return Date(timeIntervalSinceReferenceDate: previous.timeIntervalSinceReferenceDate.nextUp)
    }
}

private enum SharedWidgetFiles {
    private static func url(_ name: String) -> URL? {
        // A suite-name object is NOT evidence that a signing entitlement exists.
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetScheduleBridge.appGroupIdentifier)?
            .appendingPathComponent(name)
    }
    static func read(_ name: String) -> Data? { url(name).flatMap { try? Data(contentsOf: $0) } }
    static func write(_ data: Data, name: String) -> Bool {
        guard let destination = url(name) else { return false }
        do { try data.write(to: destination, options: .atomic); return true }
        catch { return false }
    }
}

private enum SharedKeychainSnapshot {
    static func query(account: String) -> [String: Any] {
        // Omitting agrp uses groups from the current signature. The shipping
        // entitlements put the SAME shared group first in App and Widget.
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: WidgetScheduleBridge.keychainService,
         kSecAttrAccount as String: account]
    }
    static func write(_ data: Data, account: String) -> Int32 {
        let query = query(account: account)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard status == errSecItemNotFound else { return status }
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(insert as CFDictionary, nil)
    }
    static func read(account: String) -> Data? {
        var query = query(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
}
