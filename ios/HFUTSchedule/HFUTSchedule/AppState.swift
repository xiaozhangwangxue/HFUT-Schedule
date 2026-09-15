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
    @Published var prefersHaptics: Bool {
        didSet { UserDefaults.standard.set(prefersHaptics, forKey: "prefersHaptics") }
    }

    init() {
        let savedCampus = UserDefaults.standard.string(forKey: "selectedCampus")
        campus = Campus(rawValue: savedCampus ?? "") ?? .hefei
        prefersHaptics = UserDefaults.standard.object(forKey: "prefersHaptics") as? Bool ?? true
    }
}

enum AppTab: Hashable {
    case home
    case schedule
    case services
    case me
}
