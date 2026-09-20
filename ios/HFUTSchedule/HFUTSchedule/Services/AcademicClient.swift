import Foundation

struct AcademicProgramSummary: Identifiable, Hashable {
    let id: String
    let title: String
    let requiredCredits: Double?
    let courseCount: Int
    let remark: String?
}

struct AcademicCourseSelectionTurn: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let bulletin: String
    let selectDateTimeText: String
    let addRulesText: [String]
}

struct AcademicSelectableLesson: Identifiable, Hashable {
    let id: Int
    let code: String
    let courseName: String
    let className: String
    let teachers: [String]
    let limitCount: Int
    let remark: String?
    let schedule: String?
}

struct AcademicSurveyLesson: Identifiable, Hashable {
    struct Teacher: Identifiable, Hashable {
        let id: Int
        let name: String
        let submitted: Bool
    }

    let code: String
    let courseName: String
    let department: String
    let deadline: String?
    let teachers: [Teacher]
    var id: String { code }
}

/// 转专业批次（对应 Android 版 for-std/change-major-apply/index 页面解析结果）。
struct TransferBatch: Identifiable, Hashable {
    let title: String
    let batchID: String
    let applicationDate: String
    let admissionDate: String
    var id: String { batchID }
}

/// 转专业申请里的专业条目。
struct TransferApplication: Identifiable, Hashable {
    let id: Int
    let major: String
    let department: String
    let conditions: String
    let preparedCount: Int
    let applyCount: Int
    let applyStart: String
    let applyEnd: String
    let batchName: String
}

/// 我的转专业申请。
struct TransferMyApply: Identifiable, Hashable {
    let id: Int
    let major: String
    let department: String
    let status: String
}

struct AcademicClient {
    private let mode: AcademicConnectionMode
    private let session: URLSession
    private let noRedirectSession: URLSession
    private let initialCookies: [HTTPCookie]

    init(mode: AcademicConnectionMode, cookies: [HTTPCookie]) {
        self.mode = mode
        initialCookies = cookies

        let storage = HTTPCookieStorage.shared
        for cookie in cookies {
            storage.setCookie(cookie)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = storage
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/140 Safari/537.36"
        ]
        session = URLSession(configuration: configuration)
        noRedirectSession = URLSession(
            configuration: configuration,
            delegate: AcademicNoRedirectDelegate.shared,
            delegateQueue: nil
        )
    }

    func fetchSchedule(semesterID: Int) async throws -> AcademicSyncPayload {
        let context = try await loadStudentContext()
        let query = [
            URLQueryItem(name: "bizTypeId", value: String(context.bizTypeID)),
            URLQueryItem(name: "semesterId", value: String(semesterID)),
            URLQueryItem(name: "dataId", value: String(context.studentID))
        ]
        let termData = try await get("for-std/course-table/get-data", query: query)
        let term: AcademicTermResponse
        do {
            term = try JSONDecoder().decode(AcademicTermResponse.self, from: termData)
        } catch {
            throw AcademicClientError.invalidData("课表索引解析失败：\(Self.decodingDescription(error))")
        }

        let body = try JSONSerialization.data(withJSONObject: [
            "lessonIds": term.lessonIds,
            "studentId": context.studentID,
            "weekIndex": ""
        ])
        let datumData = try await request("ws/schedule-table/datum", method: "POST", body: body)
        let datum: AcademicDatumResponse
        do {
            datum = try JSONDecoder().decode(AcademicDatumResponse.self, from: datumData)
        } catch {
            throw AcademicClientError.invalidData("课表详情解析失败：\(Self.decodingDescription(error))")
        }
        let payload = AcademicSyncPayload(term: term, datum: datum)
        guard !payload.courses().isEmpty || term.lessonIds.isEmpty else {
            throw AcademicClientError.invalidData("课表详情已返回，但没有可识别的上课记录（lessonIds：\(term.lessonIds.count)）。")
        }
        return payload
    }

    func fetchGrades() async throws -> [AcademicGradeTerm] {
        let context = try await loadStudentContext()
        let data = try await get("for-std/grade/sheet/info/\(context.studentID)")
        guard let html = String(data: data, encoding: .utf8) else {
            throw AcademicClientError.invalidData("成绩页面编码无法识别")
        }
        let terms = AcademicHTMLParser.grades(from: html)
        guard !terms.isEmpty else { throw AcademicClientError.invalidData("成绩页面中没有可识别的数据") }
        return terms
    }

    func fetchExams() async throws -> [AcademicExam] {
        let context = try await loadStudentContext()
        let data = try await get("for-std/exam-arrange/info/\(context.studentID)")
        guard let html = String(data: data, encoding: .utf8) else {
            throw AcademicClientError.invalidData("考试页面编码无法识别")
        }
        return AcademicHTMLParser.exams(from: html)
    }

    func fetchStudentInfo() async throws -> AcademicStudentInfo {
        let context = try await loadStudentContext()
        async let infoData = get("for-std/student-info/info/\(context.studentID)")
        async let profileData = get("my/profile")
        let (infoPage, profilePage) = try await (infoData, profileData)
        guard let infoHTML = String(data: infoPage, encoding: .utf8),
              let profileHTML = String(data: profilePage, encoding: .utf8) else {
            throw AcademicClientError.invalidData("学籍信息页面编码无法识别")
        }
        return AcademicHTMLParser.studentInfo(
            from: infoHTML,
            profileHTML: profileHTML,
            fallbackStudentID: String(context.studentID)
        )
    }

    func fetchProgram() async throws -> [AcademicProgramSummary] {
        let context = try await loadStudentContext()
        let data = try await get("for-std/program/root-module-json/\(context.studentID)")
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AcademicClientError.invalidData("培养方案返回格式无法识别")
        }
        let items = Self.programItems(root, path: "0")
        guard !items.isEmpty else { throw AcademicClientError.invalidData("培养方案中没有可识别的模块") }
        return items
    }

    func fetchCourseSelectionTurns() async throws -> [AcademicCourseSelectionTurn] {
        let context = try await loadStudentContext()
        _ = try await get("for-std/course-select")
        let data = try await formPost(
            "ws/for-std/course-select/open-turns",
            fields: [("bizTypeId", String(context.bizTypeID)), ("studentId", String(context.studentID))]
        )
        do {
            return try JSONDecoder().decode([AcademicCourseSelectionTurn].self, from: data)
        } catch {
            throw AcademicClientError.invalidData("选课入口解析失败：\(Self.decodingDescription(error))")
        }
    }

    func fetchSelectableLessons(turnID: Int) async throws -> [AcademicSelectableLesson] {
        _ = try await loadStudentContext()
        let data = try await formPost(
            "ws/for-std/course-select/addable-lessons",
            fields: [("turnId", String(turnID))]
        )
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw AcademicClientError.invalidData("选课课程列表返回格式无法识别")
        }
        return rows.compactMap { row in
            guard let id = Self.int(row["id"]), let code = row["code"] as? String else { return nil }
            let course = row["course"] as? [String: Any]
            let teachers = (row["teachers"] as? [[String: Any]] ?? []).compactMap { $0["nameZh"] as? String }
            return AcademicSelectableLesson(
                id: id,
                code: code,
                courseName: course?["nameZh"] as? String ?? (row["nameZh"] as? String ?? code),
                className: row["nameZh"] as? String ?? "",
                teachers: teachers,
                limitCount: Self.int(row["limitCount"]) ?? 0,
                remark: row["remark"] as? String,
                schedule: (row["dateTimePlace"] as? [String: Any])?["textZh"] as? String
            )
        }
    }

    func fetchTeachingSurveys(semesterID: Int) async throws -> [AcademicSurveyLesson] {
        let context = try await loadStudentContext()
        let data = try await get("for-std/lesson-survey/\(semesterID)/search/\(context.studentID)")
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["forStdLessonSurveySearchVms"] as? [[String: Any]] else {
            throw AcademicClientError.invalidData("评教列表返回格式无法识别")
        }
        return rows.compactMap { row in
            guard let code = row["code"] as? String else { return nil }
            let course = row["course"] as? [String: Any]
            let department = row["openDepartment"] as? [String: Any]
            let teachers = (row["lessonSurveyTasks"] as? [[String: Any]] ?? []).compactMap { task -> AcademicSurveyLesson.Teacher? in
                guard let id = Self.int(task["id"]) else { return nil }
                let teacher = task["teacher"] as? [String: Any]
                let person = teacher?["person"] as? [String: Any]
                return .init(
                    id: id,
                    name: person?["nameZh"] as? String ?? "教师",
                    submitted: task["submitted"] as? Bool ?? false
                )
            }
            return AcademicSurveyLesson(
                code: code,
                courseName: course?["nameZh"] as? String ?? code,
                department: department?["nameZh"] as? String ?? "",
                deadline: row["openEndTimeContent"] as? String,
                teachers: teachers
            )
        }
    }

    func searchCourses(
        semesterID: Int,
        courseName: String? = nil,
        className: String? = nil,
        code: String? = nil
    ) async throws -> [OfficialCourseSearchResult] {
        let context = try await loadStudentContext()
        let query = [
            URLQueryItem(name: "nameZhLike", value: className?.nilIfBlank),
            URLQueryItem(name: "queryPage__", value: "1,30"),
            URLQueryItem(name: "courseNameZhLike", value: courseName?.nilIfBlank),
            URLQueryItem(name: "codeLike", value: code?.nilIfBlank)
        ].filter { $0.value != nil }
        let data = try await get(
            "for-std/lesson-search/semester/\(semesterID)/search/\(context.studentID)",
            query: query
        )
        let response: AcademicCourseSearchEnvelope
        do {
            response = try JSONDecoder().decode(AcademicCourseSearchEnvelope.self, from: data)
        } catch {
            throw AcademicClientError.invalidData("开课查询解析失败：\(Self.decodingDescription(error))")
        }
        return response.data.compactMap { entry in
            guard let lessonID = Int(entry.lesson.id), !entry.lesson.courseName.isEmpty else { return nil }
            return OfficialCourseSearchResult(
                id: lessonID,
                courseName: entry.lesson.courseName,
                className: entry.lesson.className?.nilIfBlank,
                code: entry.lesson.code?.nilIfBlank,
                teachers: entry.lesson.teachers.map(\.name).filter { !$0.isEmpty },
                department: entry.lesson.departmentName?.nilIfBlank,
                credits: entry.lesson.credits,
                weeks: entry.lesson.suggestedWeeks?.nilIfBlank,
                schedule: entry.lesson.scheduleText?.nilIfBlank
            )
        }
    }

    private func loadStudentContext() async throws -> StudentContext {
        // Match the Android client: do not follow this redirect. The numeric
        // dataId exists in the Location header and is not the public student
        // number, so losing the 302 makes every academic endpoint unusable.
        let landingURL = AcademicPortal.url("for-std/course-table", mode: mode)
        var landingRequest = URLRequest(url: landingURL)
        attachCookies(to: &landingRequest)
        let (landingData, rawResponse) = try await noRedirectSession.data(for: landingRequest)
        guard let response = rawResponse as? HTTPURLResponse else {
            throw AcademicClientError.invalidResponse
        }
        CampusSessionStore.shared.persist(HTTPCookieStorage.shared.cookies ?? initialCookies)
        guard (200..<400).contains(response.statusCode) else {
            throw AcademicClientError.http(response.statusCode)
        }

        let location = response.value(forHTTPHeaderField: "Location") ?? ""
        if location.localizedCaseInsensitiveContains("/cas/login")
            || location.localizedCaseInsensitiveContains("/eams5-student/login") {
            throw AcademicClientError.authenticationRequired
        }
        let landingHTML = String(data: landingData, encoding: .utf8) ?? ""
        let candidates = [location, response.url?.absoluteString ?? "", landingHTML]
        guard let studentID = candidates.lazy.compactMap({
            Self.firstInteger(in: $0, pattern: #"course-table/info/(\d+)"#)
        }).first else {
            throw AcademicClientError.invalidData("未获取到教务学生标识（course-table 未返回原版所需的 302 Location）")
        }

        let data = try await get("for-std/course-table/info/\(studentID)")
        guard let html = String(data: data, encoding: .utf8),
              let bizTypeID = Self.firstInteger(in: html, pattern: #"bizTypeId\s*:\s*(\d+)"#) else {
            throw AcademicClientError.invalidData("未获取到教务业务标识")
        }
        return StudentContext(studentID: studentID, bizTypeID: bizTypeID)
    }

    private func get(_ path: String, query: [URLQueryItem] = []) async throws -> Data {
        var components = URLComponents(url: AcademicPortal.url(path, mode: mode), resolvingAgainstBaseURL: false)!
        components.queryItems = query.isEmpty ? nil : query
        return try await request(components.url!, method: "GET", body: nil)
    }

    // MARK: - 转专业

    /// 选课人数（对应上游 getSCount / ws/for-std/course-select/std-count）。
    func fetchLessonStudentCounts(lessonIDs: [Int]) async throws -> [Int: Int] {
        guard !lessonIDs.isEmpty else { return [:] }
        var result: [Int: Int] = [:]
        for chunk in stride(from: 0, to: lessonIDs.count, by: 50).map({ Array(lessonIDs[$0..<min($0 + 50, lessonIDs.count)]) }) {
            let fields = chunk.map { ("lessonIds[]", String($0)) }
            let data = try await formPost("ws/for-std/course-select/std-count", fields: fields)
            let text = String(decoding: data, as: UTF8.self)
            if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for (key, value) in root {
                    guard let id = Int(key) else { continue }
                    if let number = value as? Int { result[id] = number }
                    else if let number = value as? String, let parsed = Int(number) { result[id] = parsed }
                    else if let number = value as? Double { result[id] = Int(number) }
                }
                continue
            }
            // 形如 12345=30 或 count=30 的返回
            if let regex = try? NSRegularExpression(pattern: #"(\d+)\s*=\s*(\d+)"#) {
                for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                    guard match.numberOfRanges > 2,
                          let idRange = Range(match.range(at: 1), in: text),
                          let countRange = Range(match.range(at: 2), in: text),
                          let id = Int(text[idRange]), let count = Int(text[countRange]) else { continue }
                    result[id] = count
                }
            }
        }
        return result
    }

    func fetchTransferBatches() async throws -> [TransferBatch] {
        let context = try await loadStudentContext()
        let data = try await get("for-std/change-major-apply/index/\(context.studentID)")
        return Self.parseTransferBatches(String(decoding: data, as: UTF8.self))
    }

    func fetchTransferApplications(batchID: String) async throws -> [TransferApplication] {
        let context = try await loadStudentContext()
        let data = try await get("for-std/change-major-apply/get-applies", query: [
            URLQueryItem(name: "batchId", value: batchID),
            URLQueryItem(name: "studentId", value: String(context.studentID)),
            URLQueryItem(name: "auto", value: "false")
        ])
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["data"] as? [[String: Any]] else {
            throw AcademicClientError.invalidData("转专业列表格式无法识别")
        }
        return list.compactMap { item in
            guard let id = item["id"] as? Int else { return nil }
            let batch = item["changeMajorBatch"] as? [String: Any] ?? [:]
            return TransferApplication(
                id: id,
                major: Self.localizedName(item["major"]),
                department: Self.localizedName(item["department"]),
                conditions: (item["registrationConditions"] as? String) ?? "",
                preparedCount: item["preparedStdCount"] as? Int ?? 0,
                applyCount: item["applyStdCount"] as? Int ?? 0,
                applyStart: (batch["applyStartTime"] as? String) ?? "",
                applyEnd: (batch["applyEndTime"] as? String) ?? "",
                batchName: (batch["nameZh"] as? String) ?? ""
            )
        }
    }

    func fetchMyTransferApplications(batchID: String) async throws -> [TransferMyApply] {
        let context = try await loadStudentContext()
        let data = try await get("for-std/change-major-apply/get-my-applies", query: [
            URLQueryItem(name: "batchId", value: batchID),
            URLQueryItem(name: "studentId", value: String(context.studentID))
        ])
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["models"] as? [[String: Any]] else { return [] }
        return list.compactMap { item in
            guard let id = item["id"] as? Int,
                  let submit = item["changeMajorSubmit"] as? [String: Any] else { return nil }
            return TransferMyApply(
                id: id,
                major: Self.localizedName(submit["major"]),
                department: Self.localizedName(submit["department"]),
                status: Self.transferStatusText((item["applyStatus"] as? String) ?? "")
            )
        }
    }

    private static func localizedName(_ value: Any?) -> String {
        guard let dictionary = value as? [String: Any] else { return "" }
        return (dictionary["nameZh"] as? String) ?? (dictionary["name"] as? String) ?? ""
    }

    private static func transferStatusText(_ raw: String) -> String {
        switch raw {
        case "ACCEPTED": return "已录取"
        case "REJECTED": return "未录取"
        case "PENDING": return "待审核"
        case "": return "已提交"
        default: return raw
        }
    }

    /// 解析 .turn-panel 卡片：标题、批次号、申请时间、录取时间。
    static func parseTransferBatches(_ html: String) -> [TransferBatch] {
        var batches: [TransferBatch] = []
        let panels = html.components(separatedBy: "turn-panel")
        for panel in panels.dropFirst() {
            guard let batchID = firstMatch(in: panel, pattern: "change-major-enter[^>]*data=\"([^\"]+)\"")
                ?? firstMatch(in: panel, pattern: "data=\"([^\"]+)\"[^>]*change-major-enter") else { continue }
            let title = firstMatch(in: panel, pattern: "turn-title[^>]*>\\s*(?:<span[^>]*>)?([^<]+)")
            let application = firstMatch(in: panel, pattern: "open-date[\\s\\S]*?text-primary[^>]*>\\s*([^<]+)")
            let admission = firstMatch(in: panel, pattern: "select-date[\\s\\S]*?text-warning[^>]*>\\s*([^<]+)")
            batches.append(TransferBatch(
                title: (title ?? "转专业批次").trimmingCharacters(in: .whitespacesAndNewlines),
                batchID: batchID,
                applicationDate: (application ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                admissionDate: (admission ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }
        return batches
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = expression.firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let captured = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[captured])
    }

    private func request(_ path: String, method: String, body: Data?) async throws -> Data {
        try await request(AcademicPortal.url(path, mode: mode), method: method, body: body)
    }

    private func request(_ url: URL, method: String, body: Data?) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        attachCookies(to: &request)
        let (data, response) = try await data(for: request)
        guard AcademicPortal.isAcademicPage(response.url, mode: mode) else {
            throw AcademicClientError.authenticationRequired
        }
        return data
    }

    private func formPost(_ path: String, fields: [(String, String)]) async throws -> Data {
        var request = URLRequest(url: AcademicPortal.url(path, mode: mode))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        request.httpBody = fields.map { key, value in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(encodedKey)=\(encodedValue)"
        }.joined(separator: "&").data(using: .utf8)
        attachCookies(to: &request)
        let (data, response) = try await data(for: request)
        guard AcademicPortal.isAcademicPage(response.url, mode: mode) else {
            throw AcademicClientError.authenticationRequired
        }
        return data
    }

    private func attachCookies(to request: inout URLRequest) {
        guard let host = request.url?.host?.lowercased() else { return }
        let liveCookies = HTTPCookieStorage.shared.cookies ?? initialCookies
        let matching = liveCookies.filter { cookie in
            let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return host == domain || host.hasSuffix("." + domain)
        }
        guard !matching.isEmpty else { return }
        let fields = HTTPCookie.requestHeaderFields(with: matching)
        if let value = fields["Cookie"] { request.setValue(value, forHTTPHeaderField: "Cookie") }
    }

    private func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw AcademicClientError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else {
            throw AcademicClientError.http(response.statusCode)
        }
        return (data, response)
    }

    private static func firstInteger(in text: String, pattern: String) -> Int? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[range])
    }

    private static func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private static func programItems(_ node: [String: Any], path: String) -> [AcademicProgramSummary] {
        var values: [AcademicProgramSummary] = []
        let type = node["type"] as? [String: Any]
        let title = (type?["nameZh"] as? String) ?? (node["nameZh"] as? String)
        let require = node["requireInfo"] as? [String: Any]
        let credits = (require?["requiredCredits"] as? NSNumber)?.doubleValue
        let planCourses = node["planCourses"] as? [[String: Any]] ?? []
        if let title, !title.isEmpty {
            values.append(AcademicProgramSummary(
                id: path,
                title: title,
                requiredCredits: credits,
                courseCount: planCourses.count,
                remark: node["remark"] as? String
            ))
        }
        for (index, child) in (node["children"] as? [[String: Any]] ?? []).enumerated() {
            values += programItems(child, path: "\(path).\(index)")
        }
        return values
    }

    private static func decodingDescription(_ error: Error) -> String {
        guard let decodingError = error as? DecodingError else { return error.localizedDescription }
        switch decodingError {
        case .keyNotFound(let key, let context):
            return "缺少字段 \(path(context.codingPath, ending: key.stringValue))"
        case .typeMismatch(_, let context):
            return "字段类型不符：\(path(context.codingPath))"
        case .valueNotFound(_, let context):
            return "字段为空：\(path(context.codingPath))"
        case .dataCorrupted(let context):
            return "JSON 数据损坏：\(path(context.codingPath))"
        @unknown default:
            return error.localizedDescription
        }
    }

    private static func path(_ codingPath: [CodingKey], ending: String? = nil) -> String {
        let parts = codingPath.map(\.stringValue) + (ending.map { [$0] } ?? [])
        return parts.isEmpty ? "根节点" : parts.joined(separator: ".")
    }

    private struct StudentContext {
        let studentID: Int
        let bizTypeID: Int
    }
}

private final class AcademicNoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = AcademicNoRedirectDelegate()

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

private struct AcademicCourseSearchEnvelope: Decodable {
    let data: [Entry]
    struct Entry: Decodable { let lesson: AcademicLesson }
}

enum AcademicClientError: LocalizedError {
    case authenticationRequired
    case invalidResponse
    case http(Int)
    case invalidData(String)

    var errorDescription: String? {
        switch self {
        case .authenticationRequired: "登录会话未生效或已过期，请重新完成统一身份认证。"
        case .invalidResponse: "教务系统返回了无法识别的响应。"
        case .http(let code): "教务系统请求失败（HTTP \(code)）。"
        case .invalidData(let message): message
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

enum AcademicHTMLParser {
    static func studentInfo(from html: String, profileHTML: String, fallbackStudentID: String) -> AcademicStudentInfo {
        var fields: [String: String] = [:]
        let terms = matches(in: html, pattern: #"(?is)<dt\b[^>]*>(.*?)</dt>"#).map(clean)
        let values = matches(in: html, pattern: #"(?is)<dd\b[^>]*>(.*?)</dd>"#).map(clean)
        for (key, value) in zip(terms, values) where !key.isEmpty && !value.isEmpty { fields[key] = value }

        for pair in pairs(in: profileHTML, pattern: #"(?is)<strong\b[^>]*>(.*?)</strong>.*?<span\b[^>]*>(.*?)</span>"#) {
            let key = clean(pair.0)
            let value = clean(pair.1)
            guard !key.isEmpty, !value.isEmpty else { continue }
            fields[key] = value
        }

        // The Android app reads this value from the list item rather than the
        // dt/dd block. Preserve it so the official UniApp password can be
        // derived without ever reusing the CAS password.
        if let identity = labeledSpan(in: html, label: "证件号")
            ?? labeledSpan(in: html, label: "身份证号") {
            fields["证件号"] = identity
        }

        let studentID = labeledSpan(in: html, label: "学号") ?? fallbackStudentID
        let name = labeledSpan(in: html, label: "中文姓名") ?? fields["姓名"] ?? ""
        return AcademicStudentInfo(studentID: studentID, name: name, fields: fields)
    }

    static func grades(from html: String) -> [AcademicGradeTerm] {
        let headings = matches(in: html, pattern: #"(?is)<h3\b[^>]*>(.*?)</h3>"#).map(clean)
        let gradeTables = matches(in: html, pattern: #"(?is)<table\b[^>]*class=[\"'][^\"']*student-grade-table[^\"']*[\"'][^>]*>(.*?)</table>"#)
        let tables = gradeTables.isEmpty
            ? matches(in: html, pattern: #"(?is)<table\b[^>]*>(.*?)</table>"#).filter { table in
                rows(in: table).contains(where: { $0.count >= 7 })
            }
            : gradeTables
        return tables.enumerated().compactMap { index, table in
            let grades = rows(in: table).compactMap { cells -> AcademicGrade? in
                guard cells.count >= 7 else { return nil }
                return AcademicGrade(
                    courseName: cells[0], credits: cells[3], gpa: cells[4],
                    score: cells[6], detail: cells[5], lessonCode: cells[2]
                )
            }
            guard !grades.isEmpty else { return nil }
            return AcademicGradeTerm(term: headings.indices.contains(index) ? headings[index] : "学期 \(index + 1)", grades: grades)
        }
    }

    static func exams(from html: String) -> [AcademicExam] {
        rows(in: html).compactMap { cells in
            guard cells.count >= 3,
                  cells[1].range(of: #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}~\d{2}:\d{2}$"#, options: .regularExpression) != nil else { return nil }
            return AcademicExam(name: cells[0], dateTime: cells[1], place: cells[2])
        }.sorted { $0.dateTime < $1.dateTime }
    }

    private static func rows(in html: String) -> [[String]] {
        matches(in: html, pattern: #"(?is)<tr\b[^>]*>(.*?)</tr>"#).map { row in
            matches(in: row, pattern: #"(?is)<td\b[^>]*>(.*?)</td>"#).map(clean)
        }
    }

    private static func labeledSpan(in html: String, label: String) -> String? {
        for block in matches(in: html, pattern: #"(?is)<li\b[^>]*>(.*?)</li>"#) where clean(block).contains(label) {
            let values = matches(in: block, pattern: #"(?is)<span\b[^>]*>(.*?)</span>"#).map(clean).filter { !$0.isEmpty }
            if let value = values.last { return value }
        }
        return nil
    }

    private static func matches(in text: String, pattern: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        return expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
    }

    private static func pairs(in text: String, pattern: String) -> [(String, String)] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        return expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard match.numberOfRanges > 2,
                  let first = Range(match.range(at: 1), in: text),
                  let second = Range(match.range(at: 2), in: text) else { return nil }
            return (String(text[first]), String(text[second]))
        }
    }

    private static func clean(_ html: String) -> String {
        let withoutTags = html.replacingOccurrences(of: #"(?is)<[^>]+>"#, with: " ", options: .regularExpression)
        return withoutTags
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
