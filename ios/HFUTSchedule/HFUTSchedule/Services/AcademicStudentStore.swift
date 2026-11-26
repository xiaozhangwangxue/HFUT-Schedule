import Foundation

@MainActor
final class AcademicStudentStore: ObservableObject {
    @Published private(set) var info: AcademicStudentInfo?

    @Published private(set) var loading = false
    @Published private(set) var error: String?
    private var lastRefresh: Date?
    @Published private(set) var lifeServicePhone: String?
    private var phoneOwner: String?
    @Published private(set) var lifeServicePhoneSource: String?
    private typealias ServicePhone = (number: String, source: String)
    private var phoneTask: Task<ServicePhone?, Never>?

    /// Prefer academic personal information, then verified HuiXin personal
    /// information, then the already logged-in shower account's own profile.
    /// No phone number is requested from the user.
    func phoneForLifeServices() async -> String? {
        if let phone = StudentPhone.from(info) { lifeServicePhoneSource = "教务个人信息"; return phone }
        let owner = info?.studentID ?? ""
        if phoneOwner != owner { phoneOwner = owner; lifeServicePhone = nil; phoneTask?.cancel(); phoneTask = nil }
        if let lifeServicePhone { return lifeServicePhone }
        if let phoneTask { return await phoneTask.value?.number }
        let task = Task<ServicePhone?, Never> {
            if !owner.isEmpty, let phone = try? await CampusServiceClient.shared.fetchProfilePhone(studentID: owner) { return (phone, "慧新易校个人信息") }
            if CampusServiceClient.shared.hasSavedShowerCredentials,
               let profile = try? await CampusServiceClient.shared.fetchShowerProfile(),
               let phone = StudentPhone.normalized(profile.phone) { return (phone, "呱呱物联个人信息") }
            return StudentPhone.normalized(UserDefaults.standard.string(forKey: "bathingPhone")).map { ($0, "已保存的手机号") }
        }
        phoneTask = task
        let result = await task.value
        if phoneOwner == owner { lifeServicePhone = result?.number; lifeServicePhoneSource = result?.source; phoneTask = nil }
        return result?.number
    }

    func refresh(force: Bool = false) async {
        guard !loading, force || info == nil || lastRefresh == nil else { return }
        loading = true; error = nil
        defer { loading = false }
        do {
            let mode = AcademicConnectionMode(rawValue: UserDefaults.standard.string(forKey: "academicConnectionMode") ?? "") ?? .direct
            var value = try await AcademicClient(mode: mode, cookies: CampusSessionStore.shared.allCookies).fetchStudentInfo()
            if StudentPhone.from(value) == nil, let phone = try? await CampusServiceClient.shared.fetchProfilePhone(studentID: value.studentID) {
                var fields = value.fields; fields["手机"] = phone; fields["手机号来源"] = "慧新易校个人信息"
                value = AcademicStudentInfo(studentID: value.studentID, name: value.name, fields: fields)
            }
            guard !value.name.isEmpty || !value.fields.isEmpty else { throw AcademicClientError.invalidData("校方未返回个人信息，请刷新教务登录状态后重试") }
            replace(with: value); lastRefresh = Date()
        } catch { self.error = error.localizedDescription; AcademicServiceDiagnostics.record(context: "个人信息", error: error) }
    }

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
