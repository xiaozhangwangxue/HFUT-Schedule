import Foundation

/// 作息（学期 + 上下课时间 + 线下课程），对应 Android 版 CommunityTotalCourse。
struct CommunityTermOverview: Equatable {
    struct OfflineCourse: Identifiable, Equatable {
        let id: String
        let name: String
        let className: String
        let credit: Double
        let type: String?
    }

    var termYear: String
    var termPeriod: String
    var start: String
    var end: String
    var currentWeek: Int
    var totalWeeks: Int
    var startTimes: [String]
    var endTimes: [String]
    var offlineCourses: [OfflineCourse]

    var startDate: String { start.split(separator: " ").first.map(String.init) ?? start }
    var endDate: String { end.split(separator: " ").first.map(String.init) ?? end }
}

struct CommunityCampusMap: Identifiable, Equatable {
    let name: String
    let imageURLString: String
    var id: String { name }
    var imageURL: URL? { URL(string: imageURLString) }
}

struct CampusArrears: Equatable {
    var total: String
    var tuition: String
    var physicalExamination: String
    var dormitory: String
    var militaryTraining: String

    static let empty = CampusArrears(total: "0.00", tuition: "0.00", physicalExamination: "0.00", dormitory: "0.00", militaryTraining: "0.00")
}

struct CampusTeacher: Identifiable, Equatable {
    let name: String
    let title: String
    let department: String
    let tutor: String
    let doctorTutor: String
    let photoPath: String
    let pagePath: String

    var id: String { name + department + pagePath }

    var roles: String {
        [title, doctorTutor.isEmpty ? tutor : doctorTutor]
            .filter { !$0.isEmpty && $0 != "否" }
            .joined(separator: " · ")
    }
}

/// 原项目中「查询中心」里若干页面共用的校方接口。
final class CampusExtraAPIClient: @unchecked Sendable {
    static let shared = CampusExtraAPIClient()

    static let webVPNHost = "https://webvpn.hfut.edu.cn"
    static let teacherRoot = "http://121.251.19.138/"
    static let payFeeURLString = "http://pay.hfut.edu.cn/payment/mobileOnlinePay"
    static let onePortalRoot = "https://one.hfut.edu.cn/"

    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        session = URLSession(configuration: configuration)
    }

    // MARK: - 作息 / 学期

    /// 智慧社区课表接口：学期信息 + 上下课时间 + 线下课程。
    func fetchTermOverview() async throws -> CommunityTermOverview {
        let data = try await OfficialCampusAPIClient.shared.communityAuthorizedData(
            path: "api/business/coursearrangement/listselect"
        )
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CampusServiceError.invalidData("作息数据格式无法识别")
        }
        let payload = (root["result"] as? [String: Any]) ?? root
        let times = Self.stringArray(payload["startTime"])
        let endTimes = Self.stringArray(payload["endTime"])
        let courses = (payload["courseBasicInfoDTOList"] as? [[String: Any]] ?? []).compactMap { item -> CommunityTermOverview.OfflineCourse? in
            guard let name = Self.string(item["courseName"]) else { return nil }
            return CommunityTermOverview.OfflineCourse(
                id: Self.string(item["courseId"]) ?? name,
                name: name,
                className: Self.string(item["className"]) ?? "",
                credit: Self.double(item["credit"]) ?? 0,
                type: Self.string(item["trainingCategoryName_dictText"])
            )
        }
        return CommunityTermOverview(
            termYear: Self.string(payload["xn"]) ?? "",
            termPeriod: Self.string(payload["xq"]) ?? "",
            start: Self.string(payload["start"]) ?? "",
            end: Self.string(payload["end"]) ?? "",
            currentWeek: Int(Self.double(payload["currentWeek"]) ?? 0),
            totalWeeks: Int(Self.double(payload["totalWeekCount"]) ?? 0),
            startTimes: times,
            endTimes: endTimes,
            offlineCourses: courses
        )
    }

    // MARK: - 校园地图

    func fetchCampusMaps() async throws -> [CommunityCampusMap] {
        let data = try await OfficialCampusAPIClient.shared.communityAuthorizedData(
            path: "api//mobile/community/forumRunMap/runMapListQuery"
        )
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["result"] as? [[String: Any]] else {
            throw CampusServiceError.invalidData("校园地图数据格式无法识别")
        }
        return list.compactMap { item in
            guard let name = Self.string(item["name"]) else { return nil }
            return CommunityCampusMap(
                name: name,
                imageURLString: Self.string(item["currentMap"]) ?? ""
            )
        }
    }

    // MARK: - 欠缴学费

    func fetchArrears(studentID: String?) async throws -> CampusArrears {
        let token = try await CampusServiceClient.shared.ensureOnePortalToken()
        var components = URLComponents(string: "https://one.hfut.edu.cn/api/leaver/third/finance/arrearsForPortal")!
        components.queryItems = [
            URLQueryItem(name: "type", value: "1"),
            URLQueryItem(name: "xh", value: studentID ?? "")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(token, forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CampusServiceError.http((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["data"] as? [String: Any] else {
            throw CampusServiceError.invalidData("欠缴费用数据格式无法识别")
        }
        return CampusArrears(
            total: Self.string(payload["total"]) ?? "0.00",
            tuition: Self.string(payload["xf"]) ?? "0.00",
            physicalExamination: Self.string(payload["dstjf"]) ?? "0.00",
            dormitory: Self.string(payload["zsf"]) ?? "0.00",
            militaryTraining: Self.string(payload["dsjxf"]) ?? "0.00"
        )
    }

    // MARK: - 教师查询

    func searchTeachers(name: String, direction: String, page: Int = 1) async throws -> [CampusTeacher] {
        var components = URLComponents(string: "http://121.251.19.138/system/resource/tsites/advancesearch.jsp")!
        components.queryItems = [
            URLQueryItem(name: "teacherName", value: name),
            URLQueryItem(name: "pagesize", value: "30"),
            URLQueryItem(name: "pageindex", value: String(page)),
            URLQueryItem(name: "showlang", value: "zh_CN"),
            URLQueryItem(name: "searchDirection", value: direction),
            URLQueryItem(name: "tutorType", value: ""),
            URLQueryItem(name: "viewid", value: "1034634"),
            URLQueryItem(name: "productType", value: "0")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CampusServiceError.http((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["teacherData"] as? [[String: Any]] else {
            throw CampusServiceError.invalidData("教师数据格式无法识别")
        }
        return list.compactMap { item in
            guard let name = Self.string(item["name"]) else { return nil }
            return CampusTeacher(
                name: name,
                title: Self.string(item["prorank"]) ?? "",
                department: (Self.string(item["collegeName"]) ?? "").replacingOccurrences(of: "&nbsp;", with: ""),
                tutor: Self.string(item["gtutor"]) ?? "",
                doctorTutor: Self.string(item["doctorTutor"]) ?? "",
                photoPath: Self.string(item["picUrl"]) ?? "",
                pagePath: Self.string(item["url"]) ?? ""
            )
        }
    }

    static func teacherPhotoURL(_ teacher: CampusTeacher) -> URL? {
        guard !teacher.photoPath.isEmpty else { return nil }
        if teacher.photoPath.hasPrefix("http") { return URL(string: teacher.photoPath) }
        return URL(string: teacherRoot + teacher.photoPath)
    }

    static func teacherPageURL(_ teacher: CampusTeacher) -> URL? {
        guard !teacher.pagePath.isEmpty else { return nil }
        if teacher.pagePath.hasPrefix("http") { return URL(string: teacher.pagePath) }
        return URL(string: teacherRoot + teacher.pagePath)
    }

    static let payFeeURL = URL(string: payFeeURLString)!

    // MARK: - 解析辅助

    private static func string(_ value: Any?) -> String? {
        switch value {
        case let text as String: return text
        case let number as NSNumber: return number.stringValue
        default: return nil
        }
    }

    private static func double(_ value: Any?) -> Double? {
        if let number = value as? Double { return number }
        if let number = value as? Int { return Double(number) }
        if let text = value as? String { return Double(text) }
        return nil
    }

    private static func stringArray(_ value: Any?) -> [String] {
        (value as? [Any] ?? []).compactMap { string($0) }
    }
}
