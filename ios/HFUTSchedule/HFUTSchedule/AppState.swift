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
}

enum AppTab: Hashable {
    case home
    case schedule
    case services
    case me
}
