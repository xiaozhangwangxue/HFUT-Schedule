import Foundation

struct PlatformOccurrenceDestination: Identifiable, Equatable {
    let kind: PlatformScheduleOccurrence.Kind
    let sourceID: String
    let start: Date?
    var id: String { "\(kind.rawValue)|\(sourceID)|\(start?.timeIntervalSince1970 ?? 0)" }

    init?(url: URL) {
        guard ["hfut-schedule", "hfut_schedule"].contains(url.scheme?.lowercased() ?? ""),
              url.host?.lowercased() == "occurrence", let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let kindString = parts.queryItems?.first(where: { $0.name == "kind" })?.value,
              let kind = PlatformScheduleOccurrence.Kind(rawValue: kindString),
              let identifier = parts.queryItems?.first(where: { $0.name == "id" })?.value,
              UUID(uuidString: identifier) != nil else { return nil }
        self.kind = kind
        self.sourceID = identifier
        if let value = parts.queryItems?.first(where: { $0.name == "start" })?.value,
           let seconds = Double(value), seconds.isFinite, (0...4_102_444_800).contains(seconds) {
            start = Date(timeIntervalSince1970: seconds)
        } else { start = nil }
    }
}
