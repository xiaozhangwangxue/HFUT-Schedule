import Foundation

struct AcademicAdministrativeContact: Decodable, Identifiable {
    let id: String
    let name: String
    let photoUrl: String?
    let phone: String?
    let email: String?
}
struct AcademicAdministrativeContacts: Decodable {
    let records: [AcademicAdministrativeContact]
    let total: Int
}

enum AcademicContactsClient {
    static func fetch(page: Int = 1) async throws -> AcademicAdministrativeContacts {
        let profileData = try await ZhiJianScannerClient.shared.authorizedData(path: "/api/center/user/selectUserInfoForApp")
        guard let root = try JSONSerialization.jsonObject(with: profileData) as? [String: Any],
              let profile = root["data"] as? [String: Any], let nodeID = profile["orgId"] as? String, !nodeID.isEmpty else {
            throw AcademicClientError.invalidData("指间工大没有返回行政班组织标识")
        }
        let data = try await ZhiJianScannerClient.shared.authorizedData(path: "/api/center/userGroup/selectCrewDataByOrgIdForAPP", query: [URLQueryItem(name: "nodeId", value: nodeID), URLQueryItem(name: "isShowPhoto", value: "1"), URLQueryItem(name: "current", value: "\(page)"), URLQueryItem(name: "size", value: "200")])
        struct Envelope: Decodable { let data: AcademicAdministrativeContacts }
        return try JSONDecoder().decode(Envelope.self, from: data).data
    }
}

extension AcademicClient {
    func studentPhoto() async throws -> Data {
        let context = try await loadStudentContext()
        return try await get("students/avatar/\(context.studentID)")
    }
}
