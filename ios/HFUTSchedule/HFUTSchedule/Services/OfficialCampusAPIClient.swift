import Foundation
import Security

struct OfficialCourseSearchResult: Identifiable, Hashable {
    let id: Int
    let courseName: String
    let className: String?
    let code: String?
    let teachers: [String]
    let department: String?
    let credits: Double?
    let weeks: String?
    let schedule: String?
}

struct OfficialClassmate: Decodable, Identifiable, Hashable {
    let code: String
    let nameZh: String
    let className: String
    let gender: String
    let telephone: String?

    var id: String { code }

    private enum CodingKeys: String, CodingKey {
        case code, nameZh, className = "adminclass", gender, telephone
    }
}

struct OfficialClassroom: Decodable, Identifiable, Hashable {
    let id: Int
    let nameZh: String
    let floor: Int?
    let seatsForLesson: Int?
    let roomType: OfficialLocalizedName?
    let building: Building?

    struct Building: Decodable, Hashable {
        let nameZh: String?
        let campus: OfficialLocalizedName?
    }
}

struct OfficialFailRateRecord: Decodable, Identifiable, Hashable {
    let courseName: String
    let courseCode: String
    let terms: [Term]

    var id: String { "\(courseCode)|\(courseName)" }

    struct Term: Decodable, Hashable {
        let year: String
        let period: String
        let averageScore: Double
        let totalCount: Int
        let failCount: Int
        let successRate: Double

        private enum CodingKeys: String, CodingKey {
            case year = "xn", period = "xq", averageScore = "avgScore"
            case totalCount, failCount, successRate
        }
    }

    private enum CodingKeys: String, CodingKey {
        case courseName, courseCode = "courseMetaId", terms = "courseFailRateDTOList"
    }
}

struct OfficialLocalizedName: Decodable, Hashable {
    let nameZh: String?
}

struct OfficialBuilding: Decodable, Identifiable, Hashable {
    let nameZh: String
    let id: Int
    let campusAssoc: Int
}

struct OfficialEmptyClassroom: Decodable, Identifiable, Hashable {
    let id: Int
    let nameZh: String
    let campusNameZh: String
    let roomOccupationInfoVms: [Occupation]?

    struct Occupation: Decodable, Hashable {
        let date: String
        let startTimeString: String
        let endTimeString: String
        let activityType: String
        let activityName: String
        let teacherName: String?
    }
}

struct OfficialDormitory: Decodable, Hashable {
    let dormitory: String
    let campus: String
    let room: String
}

struct OfficialDormitoryMember: Decodable, Identifiable, Hashable {
    let username: String
    let realname: String
    var id: String { username }
}

struct OfficialDormitoryScore: Decodable, Identifiable, Hashable {
    let title: String
    let value: String
    var id: String { title }
}

struct OfficialLibraryBook: Decodable, Identifiable, Hashable {
    let title: String
    let publishers: String?
    let year: Int
    let abstract: String?
    let isbn: String
    let author: [String]
    let click: Int?
    let ds: [Origin]?
    let gc: [Position]?

    var id: String { "\(isbn)|\(title)" }
    struct Position: Decodable, Hashable {
        let cp: String
        let `in`: String
        let js: String?
    }
    struct Origin: Decodable, Hashable { let tName: String }

    private enum CodingKeys: String, CodingKey {
        case title, publishers, year, abstract, isbn, author, click, ds, gc
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        title = try values.decodeIfPresent(String.self, forKey: .title) ?? "未命名图书"
        publishers = try values.decodeIfPresent(String.self, forKey: .publishers)
        year = (try? values.decode(Int.self, forKey: .year))
            ?? Int((try? values.decode(String.self, forKey: .year)) ?? "")
            ?? 0
        abstract = try values.decodeIfPresent(String.self, forKey: .abstract)
        isbn = try values.decodeIfPresent(String.self, forKey: .isbn) ?? ""
        author = (try? values.decode([String].self, forKey: .author))
            ?? (try? values.decode(String.self, forKey: .author)).map { [$0] }
            ?? []
        click = try values.decodeIfPresent(Int.self, forKey: .click)
        ds = try values.decodeIfPresent([Origin].self, forKey: .ds)
        gc = try values.decodeIfPresent([Position].self, forKey: .gc)
    }
}

struct CommunityLibraryBook: Decodable, Identifiable, Hashable {
    let callNumber: String
    let name: String
    let author: String?
    let publisher: String?
    let year: String?
    var id: String { "\(callNumber)|\(name)" }
}

struct CommunityLibraryPosition: Decodable, Identifiable, Hashable {
    let place: String
    let status: String
    var id: String { "\(place)|\(status)" }

    private enum CodingKeys: String, CodingKey {
        case place
        case status = "status_dictText"
    }
}

struct OfficialTodayCampusApp: Identifiable, Hashable {
    let name: String
    let logoURL: URL?
    let url: URL
    var id: String { "\(name)|\(url.absoluteString)" }
}

final class OfficialCampusAPIClient: @unchecked Sendable {
    static let shared = OfficialCampusAPIClient()

    private let session: URLSession
    private let noRedirectSession: URLSession
    private let uniAppTokenAccount = "official-uniapp-id-token"
    private let communityTokenAccount = "official-community-token"
    private let uniAppAutomaticFailureKey = "officialUniAppAutomaticFailureCount"

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = .shared
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.timeoutIntervalForRequest = 40
        configuration.timeoutIntervalForResource = 60
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 HFUTSchedule-iOS"
        ]
        session = URLSession(configuration: configuration)
        noRedirectSession = URLSession(
            configuration: configuration,
            delegate: OfficialNoRedirectDelegate.shared,
            delegateQueue: nil
        )
    }

    var hasUniAppToken: Bool { SecureTokenStore.read(uniAppTokenAccount) != nil }
    var hasCommunityToken: Bool { SecureTokenStore.read(communityTokenAccount) != nil }
    var requiresManualUniAppPassword: Bool {
        UserDefaults.standard.integer(forKey: uniAppAutomaticFailureKey) >= 3
    }

    /// The UniApp account is intentionally separate from CAS. HFUT initializes
    /// it from the identity number and the Android client applies the same rule.
    static func defaultUniAppPassword(identityNumber: String) -> String? {
        let normalized = identityNumber
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count >= 6 else { return nil }
        let suffix: String
        if normalized.last?.lowercased() == "x", normalized.count >= 7 {
            suffix = String(normalized.dropLast().suffix(6))
        } else {
            suffix = String(normalized.suffix(6))
        }
        return "Hfut@#$%" + suffix
    }

    @discardableResult
    func loginUniApp(username: String, password: String) async throws -> String {
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !password.isEmpty else {
            throw OfficialCampusAPIError.uniAppAuthenticationRequired
        }
        let encrypted = try OfficialRSA.encrypt(password)
        var components = URLComponents(string: "https://jwglapp.hfut.edu.cn/token/password/passwordLogin")!
        components.queryItems = [
            URLQueryItem(name: "username", value: username.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(name: "password", value: encrypted),
            URLQueryItem(name: "appId", value: "APP_ID"),
            URLQueryItem(name: "deviceId", value: "DEVICE_ID")
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        let (data, response) = try await data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            let message = (try? JSONDecoder().decode(UniAppLoginFailure.self, from: data).message) ?? "HTTP \(response.statusCode)"
            throw OfficialCampusAPIError.loginFailed(message)
        }
        guard let token = try? JSONDecoder().decode(UniAppLoginEnvelope.self, from: data).data.idToken,
              !token.isEmpty else {
            throw OfficialCampusAPIError.invalidData("合工大教务未返回登录令牌")
        }
        try SecureTokenStore.write(token, account: uniAppTokenAccount)
        UserDefaults.standard.set(0, forKey: uniAppAutomaticFailureKey)
        return token
    }

    /// Matches the Android client: derive the independent jwglapp password
    /// from the identity number and log in without reusing the CAS password.
    /// Only expose the manual password form after three failed automatic tries.
    @discardableResult
    func ensureUniAppLogin(
        studentInfo suppliedInfo: AcademicStudentInfo? = nil,
        username suppliedUsername: String? = nil
    ) async throws -> String {
        if let token = SecureTokenStore.read(uniAppTokenAccount), !token.isEmpty { return token }

        let storedInfo: AcademicStudentInfo? = {
            guard let data = UserDefaults.standard.data(forKey: "academicStudentInfo") else { return nil }
            return try? JSONDecoder().decode(AcademicStudentInfo.self, from: data)
        }()
        let info = suppliedInfo ?? storedInfo
        let username = suppliedUsername?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyValue
            ?? info?.studentID.nonEmptyValue
            ?? UserDefaults.standard.string(forKey: "academicUsername")?.nonEmptyValue
        let identity = info?.fields.first(where: { key, _ in
            key.contains("身份证") || key.contains("证件号")
        })?.value
        guard let username, let identity, let password = Self.defaultUniAppPassword(identityNumber: identity) else {
            throw OfficialCampusAPIError.missingAutomaticCredentials
        }

        var failures = UserDefaults.standard.integer(forKey: uniAppAutomaticFailureKey)
        guard failures < 3 else { throw OfficialCampusAPIError.manualUniAppPasswordRequired }
        var lastError: Error?
        while failures < 3 {
            do {
                return try await loginUniApp(username: username, password: password)
            } catch {
                lastError = error
                failures += 1
                UserDefaults.standard.set(failures, forKey: uniAppAutomaticFailureKey)
                if failures < 3 {
                    try? await Task.sleep(for: .milliseconds(450))
                }
            }
        }
        throw OfficialCampusAPIError.manualUniAppPasswordRequiredWithCause(lastError?.localizedDescription ?? "自动登录失败")
    }

    func fetchClassmates(lessonID: Int) async throws -> [OfficialClassmate] {
        let data = try await uniAppData(path: "eams-micro-server/api/v1/lesson/student/class-mates/\(lessonID)")
        return try JSONDecoder().decode(ClassmatesEnvelope.self, from: data).data ?? []
    }

    func fetchGrades() async throws -> [AcademicGradeTerm] {
        let data = try await uniAppData(path: "eams-micro-server/api/v1/grade/student/grades")
        let values = try JSONDecoder().decode(UniAppGradeEnvelope.self, from: data).data
        let grouped = Dictionary(grouping: values, by: { $0.semester.nameZh ?? "未知学期" })
        return grouped.keys.sorted(by: >).map { term in
            AcademicGradeTerm(term: term, grades: grouped[term, default: []].map { grade in
                AcademicGrade(
                    courseName: grade.courseNameZh,
                    credits: grade.credits.formatted(.number.precision(.fractionLength(0...2))),
                    gpa: grade.gp.formatted(.number.precision(.fractionLength(0...2))),
                    score: grade.finalGrade ?? (grade.passed ? "通过" : "未通过"),
                    detail: grade.gradeDetail.replacingOccurrences(of: ";", with: " "),
                    lessonCode: grade.lessonCode
                )
            })
        }
    }

    func fetchExams() async throws -> [AcademicExam] {
        let data = try await uniAppData(path: "eams-micro-server/api/v1/exam/student/exam")
        return try JSONDecoder().decode(UniAppExamEnvelope.self, from: data).data.map { exam in
            AcademicExam(
                name: exam.courseNameZh,
                dateTime: "\(exam.examDate) \(Self.time(exam.startTime))~\(Self.time(exam.endTime))",
                place: exam.place?.split(separator: " ").last.map(String.init) ?? ""
            )
        }.sorted { $0.dateTime < $1.dateTime }
    }

    func fetchBuildings() async throws -> [OfficialBuilding] {
        // Android UniAppService always sends `campusAssoc=` even when no campus
        // filter is selected. The HFUT backend currently returns 503 when this
        // query item is omitted entirely.
        let data = try await uniAppData(url: Self.buildingsURL)
        return try JSONDecoder().decode(BuildingEnvelope.self, from: data).data
            .filter { [2, 3, 6].contains($0.campusAssoc) }
            .map { OfficialBuilding(nameZh: $0.nameZh.replacingOccurrences(of: "（宣城）", with: "").replacingOccurrences(of: "(宣)", with: ""), id: $0.id, campusAssoc: $0.campusAssoc) }
    }

    func fetchEmptyClassrooms(
        date: String,
        campusID: Int?,
        buildingIDs: [Int],
        floors: [Int],
        page: Int = 1
    ) async throws -> [OfficialEmptyClassroom] {
        let body = try Self.emptyClassroomRequestBody(
            date: date,
            campusID: campusID,
            buildingIDs: buildingIDs,
            floors: floors,
            page: page
        )
        let data = try await uniAppData(
            path: "eams-micro-server/api/v1/room/place/rooms",
            method: "POST",
            body: body
        )
        return try JSONDecoder().decode(EmptyClassroomEnvelope.self, from: data).data.data
    }

    static var buildingsURL: URL {
        var components = URLComponents(string: "https://jwglapp.hfut.edu.cn/eams-micro-server/api/v1/room/place/building")!
        components.queryItems = [URLQueryItem(name: "campusAssoc", value: "")]
        return components.url!
    }

    static func emptyClassroomRequestBody(
        date: String,
        campusID: Int?,
        buildingIDs: [Int],
        floors: [Int],
        page: Int = 1
    ) throws -> Data {
        let campusValue: Any = campusID.map { $0 } ?? NSNull()
        return try JSONSerialization.data(withJSONObject: [
            "currentPage": page,
            "date": date,
            "campusAssoc": campusValue,
            // Match Gson's Android payload exactly: selected lists are [] when
            // empty, while only an unselected campus is nullable.
            "buildingIds": buildingIDs,
            "floors": floors,
            "pageSize": 30
        ])
    }

    func searchClassrooms(name: String, page: Int = 1) async throws -> [OfficialClassroom] {
        var components = URLComponents(string: "https://jwglapp.hfut.edu.cn/eams-micro-server/api/v1/lesson/room/searchRooms")!
        components.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "queryPage__", value: "\(page),30")
        ]
        let data = try await uniAppData(url: components.url!)
        return try JSONDecoder().decode(ClassroomEnvelope.self, from: data).data.data
    }

    @discardableResult
    func refreshCommunityToken() async throws -> String {
        CampusSessionStore.shared.restoreToSharedStorage()
        var cas = URLComponents(string: "https://cas.hfut.edu.cn/cas/login")!
        cas.queryItems = [URLQueryItem(name: "service", value: "https://community.hfut.edu.cn/")]
        let (_, response) = try await noRedirectSession.data(for: URLRequest(url: cas.url!))
        guard let http = response as? HTTPURLResponse,
              (300..<400).contains(http.statusCode),
              let location = http.value(forHTTPHeaderField: "Location"),
              let ticket = URLComponents(string: location)?.queryItems?.first(where: { $0.name == "ticket" })?.value else {
            throw OfficialCampusAPIError.communityAuthenticationRequired
        }

        var validate = URLComponents(string: "https://community.hfut.edu.cn/api/sys/cas/client/validateLogin")!
        validate.queryItems = [
            URLQueryItem(name: "service", value: "https://community.hfut.edu.cn/"),
            URLQueryItem(name: "ticket", value: ticket)
        ]
        let (data, validateResponse) = try await data(for: URLRequest(url: validate.url!))
        guard (200..<300).contains(validateResponse.statusCode),
              let token = try? JSONDecoder().decode(CommunityLoginEnvelope.self, from: data).result.token,
              !token.isEmpty else {
            throw OfficialCampusAPIError.communityAuthenticationRequired
        }
        try SecureTokenStore.write(token, account: communityTokenAccount)
        CampusSessionStore.shared.persist(HTTPCookieStorage.shared.cookies ?? [])
        return token
    }

    func fetchFailRates(courseName: String, page: Int = 1, retrying: Bool = false) async throws -> [OfficialFailRateRecord] {
        let token: String
        if let saved = SecureTokenStore.read(communityTokenAccount) {
            token = saved
        } else {
            token = try await refreshCommunityToken()
        }
        var components = URLComponents(string: "https://community.hfut.edu.cn/api/business/coursefailrate/list")!
        components.queryItems = [
            URLQueryItem(name: "courseName", value: courseName),
            URLQueryItem(name: "pageNo", value: String(page)),
            URLQueryItem(name: "pageSize", value: "30")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(token, forHTTPHeaderField: "X-Access-Token")
        let (data, response) = try await data(for: request)
        if response.statusCode == 401 || response.statusCode == 403 {
            SecureTokenStore.delete(communityTokenAccount)
            throw OfficialCampusAPIError.communityAuthenticationRequired
        }
        guard (200..<300).contains(response.statusCode) else { throw OfficialCampusAPIError.http(response.statusCode) }
        do {
            return try JSONDecoder().decode(FailRateEnvelope.self, from: data).result.records
        } catch {
            guard !retrying else { throw error }
            SecureTokenStore.delete(communityTokenAccount)
            _ = try await refreshCommunityToken()
            return try await fetchFailRates(courseName: courseName, page: page, retrying: true)
        }
    }

    func fetchDormitory() async throws -> (OfficialDormitory, [OfficialDormitoryMember], [OfficialDormitoryScore]) {
        let dormData = try await communityData(path: "api//mobile/community/dormitoryHygiene/getLoginUserDormitory")
        guard let dorm = try JSONDecoder().decode(DormitoryEnvelope.self, from: dormData).result else {
            throw OfficialCampusAPIError.invalidData("智慧社区没有返回住宿信息")
        }
        var components = URLComponents(string: "https://community.hfut.edu.cn/api//mobile/profileDormitory/list")!
        components.queryItems = [
            URLQueryItem(name: "campus", value: dorm.campus),
            URLQueryItem(name: "room", value: dorm.room),
            URLQueryItem(name: "dormitory", value: dorm.dormitory)
        ]
        let membersURL = components.url!
        async let membersData = communityData(url: membersURL)
        async let scoresData = communityData(path: "api//mobile/community/dormitoryHygiene/public/gridManagementDormitoryCheck")
        let (memberPayload, scorePayload) = try await (membersData, scoresData)
        let profiles = try JSONDecoder().decode(DormitoryMemberEnvelope.self, from: memberPayload).result?.profileList ?? []
        let members = profiles.flatMap(\.userList)
        let scores = try JSONDecoder().decode(DormitoryScoreEnvelope.self, from: scorePayload).result
        return (dorm, members, scores)
    }

    func searchLibrary(keyword: String, page: Int = 1) async throws -> [OfficialLibraryBook] {
        var request = URLRequest(url: URL(string: "https://lib.hfut.edu.cn/svc/space/mate/search")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "page": page,
            "size": 30,
            "sort": 1,
            "conditions": [["value": keyword]],
            "source": ["Cats": ["gczzts", "wgdzs"]]
        ])
        let (data, response) = try await self.data(for: request)
        guard (200..<300).contains(response.statusCode) else { throw OfficialCampusAPIError.http(response.statusCode) }
        return try JSONDecoder().decode(LibrarySearchEnvelope.self, from: data).data.rows
    }

    func searchCommunityLibrary(keyword: String, page: Int = 1) async throws -> [CommunityLibraryBook] {
        var components = URLComponents(string: "https://community.hfut.edu.cn/api/business/book/search")!
        components.queryItems = [
            URLQueryItem(name: "name", value: keyword),
            URLQueryItem(name: "pageNo", value: String(page)),
            URLQueryItem(name: "pageSize", value: "30")
        ]
        let data = try await communityData(url: components.url!)
        return try JSONDecoder().decode(CommunityLibraryEnvelope.self, from: data).result.records
    }

    func fetchCommunityLibraryPositions(callNumber: String) async throws -> [CommunityLibraryPosition] {
        var components = URLComponents(string: "https://community.hfut.edu.cn/api/business/book/detail")!
        components.queryItems = [URLQueryItem(name: "callNo", value: callNumber)]
        let data = try await communityData(url: components.url!)
        return try JSONDecoder().decode(CommunityLibraryPositionEnvelope.self, from: data).result
    }

    func fetchTodayCampusApps() async throws -> [OfficialTodayCampusApp] {
        let data = try await communityData(path: "api//mobile/community/application/listApplication")
        let groups = try JSONDecoder().decode(TodayCampusCommunityEnvelope.self, from: data).result
        return groups.flatMap(\.subList).compactMap { item in
            guard let rawURL = item.url,
                  rawURL.hasPrefix("https://stu.hfut.edu.cn/") || rawURL.hasPrefix("http://stu.hfut.edu.cn/"),
                  let url = URL(string: rawURL) else { return nil }
            return OfficialTodayCampusApp(name: item.name, logoURL: URL(string: item.logo), url: url)
        }
    }

    private func authorizedUniAppData(url: URL, token: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(token, forHTTPHeaderField: "Authorization")
        let (data, response) = try await data(for: request)
        if response.statusCode == 401 || response.statusCode == 403 {
            SecureTokenStore.delete(uniAppTokenAccount)
            throw OfficialCampusAPIError.uniAppAuthenticationRequired
        }
        guard (200..<300).contains(response.statusCode) else { throw OfficialCampusAPIError.http(response.statusCode) }
        return data
    }

    private func communityData(path: String) async throws -> Data {
        try await communityData(url: URL(string: path, relativeTo: URL(string: "https://community.hfut.edu.cn/")!)!.absoluteURL)
    }

    /// 供查询中心其它页面复用的智慧社区鉴权请求。
    func communityAuthorizedData(path: String) async throws -> Data {
        try await communityData(path: path)
    }

    private func communityData(url: URL) async throws -> Data {
        let token: String
        if let saved = SecureTokenStore.read(communityTokenAccount) { token = saved }
        else { token = try await refreshCommunityToken() }
        var request = URLRequest(url: url)
        request.setValue(token, forHTTPHeaderField: "X-Access-Token")
        let (data, response) = try await self.data(for: request)
        if response.statusCode == 401 || response.statusCode == 403 {
            SecureTokenStore.delete(communityTokenAccount)
            throw OfficialCampusAPIError.communityAuthenticationRequired
        }
        guard (200..<300).contains(response.statusCode) else { throw OfficialCampusAPIError.http(response.statusCode) }
        return data
    }

    private func uniAppData(path: String, method: String = "GET", body: Data? = nil, retry: Int = 0) async throws -> Data {
        let url = URL(string: path, relativeTo: URL(string: "https://jwglapp.hfut.edu.cn/")!)!.absoluteURL
        return try await uniAppData(url: url, method: method, body: body, retry: retry)
    }

    private func uniAppData(url: URL, method: String = "GET", body: Data? = nil, retry: Int = 0) async throws -> Data {
        _ = try await ensureUniAppLogin()
        guard let token = SecureTokenStore.read(uniAppTokenAccount) else { throw OfficialCampusAPIError.uniAppAuthenticationRequired }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        request.setValue(token, forHTTPHeaderField: "Authorization")
        let (data, response) = try await self.data(for: request)
        if response.statusCode == 401 || response.statusCode == 403 {
            SecureTokenStore.delete(uniAppTokenAccount)
            if retry < 1 {
                _ = try await ensureUniAppLogin()
                return try await uniAppData(url: url, method: method, body: body, retry: retry + 1)
            }
            throw OfficialCampusAPIError.uniAppAuthenticationRequired
        }
        if [502, 503, 504].contains(response.statusCode), retry < 2 {
            try? await Task.sleep(for: .milliseconds(700 * (retry + 1)))
            return try await uniAppData(url: url, method: method, body: body, retry: retry + 1)
        }
        guard (200..<300).contains(response.statusCode) else { throw OfficialCampusAPIError.http(response.statusCode) }
        return data
    }

    private static func time(_ value: Int) -> String {
        String(format: "%02d:%02d", value / 100, value % 100)
    }

    private func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw OfficialCampusAPIError.invalidResponse }
        return (data, response)
    }
}

enum OfficialCampusAPIError: LocalizedError {
    case invalidResponse
    case invalidData(String)
    case http(Int)
    case loginFailed(String)
    case uniAppAuthenticationRequired
    case missingAutomaticCredentials
    case manualUniAppPasswordRequired
    case manualUniAppPasswordRequiredWithCause(String)
    case communityAuthenticationRequired

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "校方接口返回了无法识别的响应。"
        case .invalidData(let message): message
        case .http(let code): "校方接口请求失败（HTTP \(code)）。"
        case .loginFailed(let message): "合工大教务登录失败：\(message)"
        case .uniAppAuthenticationRequired: "此功能使用校方“合工大教务”API，需要教务系统密码完成一次令牌登录。"
        case .missingAutomaticCredentials: "尚未取得学号或证件号，请先完成一次统一身份认证，应用会自动使用教务默认密码登录。"
        case .manualUniAppPasswordRequired: "教务默认密码已自动尝试 3 次仍未成功，请输入修改后的教务系统密码。"
        case .manualUniAppPasswordRequiredWithCause(let cause): "教务默认密码已自动尝试 3 次仍未成功，请输入修改后的教务系统密码。\n\(cause)"
        case .communityAuthenticationRequired: "智慧社区令牌未生效，请在“选项 → 前往安全登录”重新完成统一身份认证。"
        }
    }
}

private extension String {
    var nonEmptyValue: String? { isEmpty ? nil : self }
}

private struct UniAppLoginEnvelope: Decodable { let data: DataValue; struct DataValue: Decodable { let idToken: String } }
private struct UniAppLoginFailure: Decodable { let message: String }
private struct ClassmatesEnvelope: Decodable { let data: [OfficialClassmate]? }
private struct ClassroomEnvelope: Decodable { let data: Page; struct Page: Decodable { let data: [OfficialClassroom] } }
private struct BuildingEnvelope: Decodable { let data: [OfficialBuilding] }
private struct EmptyClassroomEnvelope: Decodable { let data: Page; struct Page: Decodable { let data: [OfficialEmptyClassroom] } }
private struct UniAppGradeEnvelope: Decodable {
    let data: [Grade]
    struct Grade: Decodable {
        let courseNameZh: String
        let lessonCode: String
        let semester: OfficialLocalizedName
        let passed: Bool
        let finalGrade: String?
        let gradeDetail: String
        let credits: Double
        let gp: Double
    }
}
private struct UniAppExamEnvelope: Decodable {
    let data: [Exam]
    struct Exam: Decodable {
        let courseNameZh: String
        let examDate: String
        let startTime: Int
        let endTime: Int
        let place: String?
    }
}
private struct CommunityLoginEnvelope: Decodable { let result: ResultValue; struct ResultValue: Decodable { let token: String? } }
private struct FailRateEnvelope: Decodable { let result: ResultValue; struct ResultValue: Decodable { let records: [OfficialFailRateRecord] } }
private struct DormitoryEnvelope: Decodable { let result: OfficialDormitory? }
private struct DormitoryMemberEnvelope: Decodable {
    let result: ResultValue?
    struct ResultValue: Decodable { let profileList: [Profile] }
    struct Profile: Decodable { let userList: [OfficialDormitoryMember] }
}
private struct DormitoryScoreEnvelope: Decodable { let result: [OfficialDormitoryScore] }
private struct LibrarySearchEnvelope: Decodable {
    let data: DataValue
    struct DataValue: Decodable { let rows: [OfficialLibraryBook] }
}
private struct CommunityLibraryEnvelope: Decodable {
    let result: ResultValue
    struct ResultValue: Decodable { let records: [CommunityLibraryBook] }
}
private struct CommunityLibraryPositionEnvelope: Decodable {
    let result: [CommunityLibraryPosition]
}
private struct TodayCampusCommunityEnvelope: Decodable {
    let result: [Group]
    struct Group: Decodable { let category: String; let subList: [Item] }
    struct Item: Decodable { let name: String; let logo: String; let url: String? }
}

private enum SecureTokenStore {
    private static let service = "com.xiaozhangwangxue.hfutschedule.official-api"

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String, account: String) throws {
        delete(account)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(value.utf8)
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw OfficialCampusAPIError.invalidData("安全存储令牌失败（\(status)）") }
    }

    static func delete(_ account: String) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ] as CFDictionary)
    }
}

private enum OfficialRSA {
    private static let publicKey = "MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCFY5N+9UX+0BF+xz1svFguI4CIDvmQTfINkOZ1HOO3ltBNHGQTUirUPQTyEph/+q/l8b16YYw3I2fyTH6y15s3tHf5jMei+R/20jFRGo5udwVJUwq/RozKQIRzCtPYkXG4YWBnHKhXalZ5K2fhd5i/QtB016nVugH/7eiBDWbKVwIDAQAB"

    static func encrypt(_ plaintext: String) throws -> String {
        guard let x509 = Data(base64Encoded: publicKey),
              let rawKey = stripSubjectPublicKeyInfo(x509) else {
            throw OfficialCampusAPIError.invalidData("教务公钥无效")
        }
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: 1024
        ]
        var createError: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(rawKey as CFData, attributes as CFDictionary, &createError) else {
            if let error = createError?.takeRetainedValue() { throw error }
            throw OfficialCampusAPIError.invalidData("无法载入教务公钥")
        }
        var encryptionError: Unmanaged<CFError>?
        guard let encrypted = SecKeyCreateEncryptedData(key, .rsaEncryptionPKCS1, Data(plaintext.utf8) as CFData, &encryptionError) else {
            if let error = encryptionError?.takeRetainedValue() { throw error }
            throw OfficialCampusAPIError.invalidData("教务密码加密失败")
        }
        return (encrypted as Data).base64EncodedString()
    }

    private static func stripSubjectPublicKeyInfo(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard let bitString = bytes.indices.first(where: { index in
            index + 4 < bytes.count && bytes[index] == 0x03 && bytes[index + 3] == 0x00 && bytes[index + 4] == 0x30
        }) else { return nil }
        return Data(bytes[(bitString + 4)...])
    }
}

private final class OfficialNoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = OfficialNoRedirectDelegate()
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
