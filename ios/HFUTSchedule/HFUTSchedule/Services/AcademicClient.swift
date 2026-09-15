import Foundation

struct AcademicClient {
    private let mode: AcademicConnectionMode
    private let session: URLSession

    init(mode: AcademicConnectionMode, cookies: [HTTPCookie]) {
        self.mode = mode

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

    private func loadStudentContext() async throws -> StudentContext {
        let (data, response) = try await data(for: URLRequest(url: AcademicPortal.url("for-std/course-table", mode: mode)))
        guard AcademicPortal.isAcademicPage(response.url, mode: mode) else {
            throw AcademicClientError.authenticationRequired
        }
        let urlText = response.url?.absoluteString ?? ""
        guard let studentID = Self.firstInteger(in: urlText, pattern: #"course-table/info/(\d+)"#) else {
            throw AcademicClientError.invalidData("未获取到教务学生标识，请重新登录")
        }
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

    private func request(_ path: String, method: String, body: Data?) async throws -> Data {
        try await request(AcademicPortal.url(path, mode: mode), method: method, body: body)
    }

    private func request(_ url: URL, method: String, body: Data?) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await data(for: request)
        guard AcademicPortal.isAcademicPage(response.url, mode: mode) else {
            throw AcademicClientError.authenticationRequired
        }
        return data
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
