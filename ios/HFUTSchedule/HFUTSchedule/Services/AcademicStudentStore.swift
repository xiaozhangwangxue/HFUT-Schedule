import Foundation

@MainActor
final class AcademicStudentStore: ObservableObject {
    @Published private(set) var info: AcademicStudentInfo?

    private let key = "academicStudentInfo"

    init() {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        info = try? JSONDecoder().decode(AcademicStudentInfo.self, from: data)
    }

    func replace(with value: AcademicStudentInfo) {
        info = value
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
