import SwiftUI

@MainActor
final class AppState: ObservableObject {
    enum Campus: String, CaseIterable, Identifiable {
        case hefei = "合肥校区"
        case xuancheng = "宣城校区"

        var id: String { rawValue }
    }

    @Published var campus: Campus {
        didSet { UserDefaults.standard.set(campus.rawValue, forKey: "selectedCampus") }
    }
    @Published var selectedTab: AppTab = .home
    @Published var pendingFeatureID: Int?
    @Published var shouldPresentLogin = false
    @Published var prefersHaptics: Bool {
        didSet { UserDefaults.standard.set(prefersHaptics, forKey: "prefersHaptics") }
    }

    init() {
        let savedCampus = UserDefaults.standard.string(forKey: "selectedCampus")
        campus = Campus(rawValue: savedCampus ?? "") ?? .hefei
        prefersHaptics = UserDefaults.standard.object(forKey: "prefersHaptics") as? Bool ?? true
        consumePendingDestination()
    }

    func consumePendingDestination() {
        let featureID = UserDefaults.standard.integer(forKey: "pendingFeatureID")
        if featureID > 0 {
            pendingFeatureID = featureID
            UserDefaults.standard.removeObject(forKey: "pendingFeatureID")
        }
        guard let value = UserDefaults.standard.string(forKey: "pendingDestination") else { return }
        switch value {
        case "schedule": selectedTab = .schedule
        case "services": selectedTab = .services
        default: break
        }
        UserDefaults.standard.removeObject(forKey: "pendingDestination")
    }

    func consumePendingFeature() -> CampusFeature? {
        defer { pendingFeatureID = nil }
        guard let pendingFeatureID else { return nil }
        return FeatureCatalog.all.first { $0.id == pendingFeatureID }
    }

    func open(_ url: URL) {
        guard ["hfut-schedule", "hfut_schedule"].contains(url.scheme?.lowercased() ?? "") else { return }

        if let mode = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "mode" })?.value?.lowercased(),
           [AcademicConnectionMode.direct.rawValue.lowercased(), "webvpn"].contains(mode) {
            UserDefaults.standard.set(
                mode == "webvpn" ? AcademicConnectionMode.webVPN.rawValue : AcademicConnectionMode.direct.rawValue,
                forKey: "academicConnectionMode"
            )
        }
        if URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.contains(where: { $0.name == "login" && $0.value == "1" }) == true {
            shouldPresentLogin = true
        }
        if let featureText = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "feature" })?.value,
           let featureID = Int(featureText), FeatureCatalog.all.contains(where: { $0.id == featureID }) {
            pendingFeatureID = featureID
            selectedTab = .services
        }

        let destination = [url.host, url.pathComponents.dropFirst().first]
            .compactMap { $0?.lowercased() }
            .first { !$0.isEmpty }

        switch destination {
        case "schedule", "timetable", "课程表":
            selectedTab = .schedule
        case "home", "focus", "聚焦":
            selectedTab = .home
        case "services", "query", "查询中心":
            selectedTab = .services
        case "profile", "options", "选项":
            selectedTab = .me
        default:
            break
        }
    }

    func consumeLoginRequest() -> Bool {
        defer { shouldPresentLogin = false }
        return shouldPresentLogin
    }
}

enum AppTab: Hashable {
    case home
    case schedule
    case services
    case me
}
