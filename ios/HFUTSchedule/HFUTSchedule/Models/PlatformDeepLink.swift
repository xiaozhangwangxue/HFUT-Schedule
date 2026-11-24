import Foundation

enum PlatformDeepLinkURL {
    /// Foundation follows RFC URL-scheme grammar, which rejects underscores.
    /// Normalize the original Android spelling before asking URL to parse it.
    static func url(from text: String) -> URL? {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized: String
        if raw.lowercased().hasPrefix("hfut_schedule://") {
            normalized = "hfut-schedule://" + raw.dropFirst("hfut_schedule://".count)
        } else { normalized = raw }
        guard let url = URL(string: normalized), url.scheme?.lowercased() == "hfut-schedule" else { return nil }
        return url
    }
}

struct PlatformDeepLinkRequest: Identifiable, Hashable {
    let id = UUID()
    let target: String
    let arguments: [String: String]
    static let featureIDs: [String: Int] = [
        "admission": 41, "all_exam": 6, "bus": 20, "all_department": 17,
        "dormitory": 14, "fee": 32, "washing": 40, "holiday": 38, "life": 28,
        "notification_center": 15, "office_hall": 43, "person_info": 10,
        "scan_qr_code": 2, "school_card": 1, "supabase_home": 39, "track": 48,
        "web_folder": 11, "webvpn": 42, "work": 37, "library": 19,
        "classroom": 24, "exam": 6, "grade": 7, "program": 18,
        "all_course": 9, "work_and_rest": 26, "program_competition": 18
    ]
    static let specialTargets: Set<String> = [
        "settings_about", "settings_about_developer", "settings_appearance", "settings_backup",
        "settings_configurations", "settings_deeplink", "settings_network", "term_report", "version_info",
        "library_borrowed", "update_successfully", "agreement", "login", "average_grade", "all_program",
        "add_event", "news", "teacher_search", "fail_rate", "course_classmates", "ai", "home"
    ]
    init?(url: URL) {
        guard ["hfut-schedule", "hfut_schedule"].contains(url.scheme?.lowercased() ?? ""),
              let target = url.host?.lowercased(), Self.featureIDs[target] != nil || Self.specialTargets.contains(target),
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        self.target = target
        let allowed = ["keyword", "name", "course_name", "lesson_code", "lesson_id", "page"]
        var args: [String: String] = [:]
        for item in parts.queryItems ?? [] where allowed.contains(item.name) {
            guard let value = item.value, value.count <= 1_024 else { continue }
            // First value wins, matching Android Uri.getQueryParameter.
            if args[item.name] == nil { args[item.name] = value }
        }
        arguments = args
    }
    init?(rawValue: String) {
        guard let url = PlatformDeepLinkURL.url(from: rawValue) else { return nil }
        self.init(url: url)
    }
    var featureID: Int? { Self.featureIDs[target] }
    var lessonID: Int? {
        guard let text = arguments["lesson_id"], let value = Int(text), value > 0, value <= Int(Int32.max) else { return nil }
        return value
    }
}
