import Foundation

struct AcademicSubmissionResult: Equatable {
    let success: Bool
    let message: String
}

struct ProgramProgressCourse: Decodable, Identifiable {
    var id: String { code }
    let code: String
    let nameZh: String
    let credits: Double
    let terms: [String]
    let compulsory: Bool
    let resultType: String
    let score: Double?
    let rank: String?
    let gp: Double?
    var status: String { ["PASSED": "已修", "TAKING": "在修", "UNREPAIRED": "未修", "FAILED": "挂科"][resultType] ?? resultType }
}
struct ProgramProgressModule: Decodable, Identifiable {
    var id: Int64 { moduleId }
    let moduleId: Int64
    let nameZh: String
    let allCourseList: [ProgramProgressCourse]
    let allModuleList: [ProgramProgressModule]
}
struct ProgramProgressDetails: Decodable {
    let moduleList: [ProgramProgressModule]
    let outerCourseList: [ProgramProgressCourse]
}
struct AcademicProgramSearchItem: Decodable, Identifiable {
    let id: Int
    let nameZh: String
    let grade: String
    let department: OfficialLocalizedName
    let major: OfficialLocalizedName
}
struct AcademicConfirmedCourse: Decodable, Identifiable {
    var id: String { courseCode }
    let courseName: String
    let courseCode: String
    let credits: Double
}
struct AcademicSurveyForm: Decodable {
    let lessonSurveyLesson: Lesson
    let survey: Questions
    struct Lesson: Decodable { let surveyAssoc: Int }
    struct Questions: Decodable { let radioQuestions: [Radio]; let blankQuestions: [Blank] }
    struct Radio: Decodable, Identifiable {
        let id: String; let title: String; let options: [Option]
        struct Option: Decodable, Hashable { let name: String; let score: Int }
    }
    struct Blank: Decodable, Identifiable { let id: String; let title: String }
}
struct AcademicDetailField: Identifiable, Hashable {
    var id: String { label + "|" + value }
    let label: String
    let value: String
}

struct AcademicSurveyDraft {
    let choices: [String: String]
    let comments: [String: String]
    static func highest(form: AcademicSurveyForm, comment: String) throws -> AcademicSurveyDraft {
        var choices: [String: String] = [:]
        for question in form.survey.radioQuestions {
            guard let option = question.options.max(by: { $0.score < $1.score }) else {
                throw AcademicClientError.invalidData("问卷题目没有可选答案，未发送该问卷")
            }
            choices[question.id] = option.name
        }
        return AcademicSurveyDraft(choices: choices, comments: Dictionary(uniqueKeysWithValues: form.survey.blankQuestions.map { ($0.id, comment) }))
    }
}

struct AcademicBulkSurveyResult: Identifiable, Codable {
    enum Status: String, Codable { case waiting, running, confirmed, unconfirmed, failed }
    let id: Int
    let teacher: String
    let course: String
    var status: Status = .waiting
    var message = "等待提交"
    static func allConfirmed(_ results: [AcademicBulkSurveyResult]) -> Bool {
        !results.isEmpty && results.allSatisfy { $0.status == .confirmed }
    }
}

extension OfficialCampusAPIClient {
    func searchAcademicPrograms(keyword: String, page: Int) async throws -> [AcademicProgramSearchItem] {
        let data = try await uniAppAuthorizedData(path: "eams-micro-server/api/v1/plan/search/major", method: "POST", body: JSONSerialization.data(withJSONObject: ["nameZhLike": keyword, "currentPage": page, "pageSize": 30]))
        struct Envelope: Decodable { let data: Page; struct Page: Decodable { let data: [AcademicProgramSearchItem] } }
        return try JSONDecoder().decode(Envelope.self, from: data).data.data
    }
    func academicProgram(id: Int) async throws -> AcademicProgramNode {
        let data = try await uniAppAuthorizedData(path: "eams-micro-server/api/v1/plan/search/major/plan-courses/\(id)")
        guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any], let root = envelope["data"] as? [String: Any] else { throw AcademicClientError.invalidData("培养方案详情格式无法识别") }
        return AcademicClient.programNode(root, path: "program-\(id)")
    }
}

extension AcademicClient {
    func fetchProgramProgressDetails() async throws -> ProgramProgressDetails {
        let context = try await loadStudentContext()
        return try JSONDecoder().decode(ProgramProgressDetails.self, from: await get("for-std/program-completion-preview/json/\(context.studentID)"))
    }
    func fetchCourseConfirmation(semesterID: Int) async throws -> [String: [AcademicConfirmedCourse]] {
        let context = try await loadStudentContext()
        let data = try await formPost("for-std/course-select-confirm/info", fields: [("studentId", "\(context.studentID)"), ("semesterId", "\(semesterID)")])
        struct Response: Decodable { let detailModels: [String: [AcademicConfirmedCourse]] }
        return try JSONDecoder().decode(Response.self, from: data).detailModels
    }
    func fetchSelectedLessons(turnID: Int) async throws -> [AcademicSelectableLesson] {
        let context = try await loadStudentContext()
        let data = try await formPost("ws/for-std/course-select/selected-lessons", fields: [("studentId", "\(context.studentID)"), ("turnId", "\(turnID)")])
        return try Self.parseSelectionLessons(data)
    }
    func lessonSchedule(lessonIDs: [Int]) async throws -> [Course] {
        let context = try await loadStudentContext()
        let body = try JSONSerialization.data(withJSONObject: ["lessonIds": lessonIDs, "studentId": context.studentID, "weekIndex": ""])
        let datum = try JSONDecoder().decode(AcademicDatumResponse.self, from: await request("ws/schedule-table/datum", method: "POST", body: body))
        let term = AcademicTermResponse(lessonIds: lessonIDs, timeTableLayoutId: nil, currentWeek: nil)
        return AcademicSyncPayload(term: term, datum: datum).courses()
    }
    static func parseSelectionLessons(_ data: Data) throws -> [AcademicSelectableLesson] {
        let root = try JSONSerialization.jsonObject(with: data)
        guard let rows = root as? [[String: Any]] ?? (root as? [String: Any])?["data"] as? [[String: Any]] else { throw AcademicClientError.invalidData("选课列表格式无法识别，请刷新教务登录状态后重试") }
        return rows.compactMap { row in
            guard let id = (row["id"] as? Int) ?? (row["id"] as? String).flatMap(Int.init) else { return nil }
            let course = row["course"] as? [String: Any] ?? [:]
            return AcademicSelectableLesson(id: id, code: row["code"] as? String ?? "", courseName: course["nameZh"] as? String ?? row["nameZh"] as? String ?? "课程", className: row["nameZh"] as? String ?? "", teachers: (row["teachers"] as? [[String: Any]] ?? []).compactMap { $0["nameZh"] as? String }, limitCount: row["limitCount"] as? Int ?? 0, remark: row["remark"] as? String, schedule: (row["dateTimePlace"] as? [String: Any])?["textZh"] as? String)
        }
    }
    /// This method only runs following the user's explicit selection confirmation.
    func submitCourseSelection(turnID: Int, lessonID: Int, dropping: Bool) async throws -> AcademicSubmissionResult {
        let context = try await loadStudentContext()
        _ = try await get("for-std/course-select")
        let data = try await formPost("ws/for-std/course-select/\(dropping ? "drop" : "add")-request", fields: [("studentAssoc", "\(context.studentID)"), ("lessonAssoc", "\(lessonID)"), ("courseSelectTurnAssoc", "\(turnID)")])
        let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let requestID = (try? JSONDecoder().decode(String.self, from: data)) ?? raw
        guard !requestID.isEmpty, !requestID.contains("<"), !requestID.hasPrefix("{") else { throw AcademicClientError.invalidData("校方没有返回选课请求标识") }
        let response = try await formPost("ws/for-std/course-select/add-drop-response", fields: [("studentId", "\(context.studentID)"), ("requestId", requestID)])
        return try Self.parseSubmission(response)
    }
    static func parseSubmission(_ data: Data) throws -> AcademicSubmissionResult {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AcademicClientError.invalidData("校方操作响应无法识别") }
        let success = root["success"] as? Bool ?? root["result"] as? Bool ?? false
        let error = root["errorMessage"] as? [String: Any]
        let errors = (root["errors"] as? [[String: Any]] ?? []).compactMap { $0["textZh"] as? String }.joined(separator: "；")
        return AcademicSubmissionResult(success: success, message: success ? "操作成功" : error?["textZh"] as? String ?? (errors.isEmpty ? (root["message"] as? String ?? "校方拒绝了操作") : errors))
    }
    func fetchSurveyForm(taskID: Int) async throws -> AcademicSurveyForm {
        let context = try await loadStudentContext()
        _ = try await get("for-std/lesson-survey/start-survey/\(taskID)", query: [URLQueryItem(name: "REDIRECT_URL", value: "/for-std/lesson-survey/semester-index/\(context.studentID)")])
        return try JSONDecoder().decode(AcademicSurveyForm.self, from: await get("for-std/lesson-survey/start-survey/\(taskID)/get-data"))
    }
    func submitSurvey(taskID: Int, form: AcademicSurveyForm, choices: [String: String], comments: [String: String]) async throws {
        guard form.survey.radioQuestions.allSatisfy({ question in question.options.contains { $0.name == choices[question.id] } }) else { throw AcademicClientError.invalidData("请完成每道评价题") }
        let body: [String: Any] = ["surveyAssoc": form.lessonSurveyLesson.surveyAssoc, "lessonSurveyTaskAssoc": taskID, "radioQuestionAnswers": form.survey.radioQuestions.map { ["questionId": $0.id, "optionName": choices[$0.id] ?? ""] }, "blankQuestionAnswers": form.survey.blankQuestions.map { ["questionId": $0.id, "content": comments[$0.id] ?? ""] }]
        let data = try await request("for-std/lesson-survey/submit-survey", method: "POST", body: JSONSerialization.data(withJSONObject: body))
        if let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], root["success"] as? Bool == false {
            throw AcademicClientError.invalidData(root["message"] as? String ?? "评教提交未成功")
        }
        do { try await confirmSurveySubmission(taskID: taskID) }
        catch { throw AcademicWorkflowError.surveyUnconfirmed(error.localizedDescription) }
    }
    func confirmSurveySubmission(taskID: Int) async throws {
        let lessons = try await fetchTeachingSurveys(semesterID: AcademicPortal.currentSemesterID)
        try Self.requireSurveySubmitted(taskID: taskID, lessons: lessons)
    }
    static func requireSurveySubmitted(taskID: Int, lessons: [AcademicSurveyLesson]) throws {
        guard let task = lessons.flatMap(\.teachers).first(where: { $0.id == taskID }), task.submitted else {
            throw AcademicClientError.invalidData("校方尚未将该问卷标记为已提交")
        }
    }
    func submitTransfer(batchID: String, submitID: Int, telephone: String, email: String, remark: String) async throws -> AcademicSubmissionResult {
        guard !telephone.trimmingCharacters(in: .whitespaces).isEmpty else { throw AcademicClientError.invalidData("请填写联系电话") }
        let context = try await loadStudentContext()
        let redirect = "/for-std/change-major-apply/apply?PARENT_URL=/for-std/change-major-apply/index/\(context.studentID)&batchId=\(batchID)&studentId=\(context.studentID)"
        _ = try await get("for-std/change-major-apply/new", query: [URLQueryItem(name: "REDIRECT_URL", value: redirect), URLQueryItem(name: "submitId", value: "\(submitID)"), URLQueryItem(name: "batchId", value: batchID), URLQueryItem(name: "studentId", value: "\(context.studentID)")])
        let boundary = "HFUT-\(UUID().uuidString)"
        var data = Data()
        let fields = [("stdAlterReasonAssoc", "1286"), ("applyRemark", remark), ("telephone", telephone), ("email", email), ("REDIRECT_URL", redirect), ("changeMajorBatchAssoc", batchID), ("studentAssoc", "\(context.studentID)"), ("changeMajorSubmitAssoc", "\(submitID)")]
        for (key, value) in fields { data.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n\(value)\r\n".utf8)) }
        data.append(Data("--\(boundary)--\r\n".utf8))
        return try Self.parseSubmission(await request("for-std/change-major-apply/save", method: "POST", body: data, contentType: "multipart/form-data; boundary=\(boundary)"))
    }
    func cancelTransfer(batchID: String, applicationID: Int) async throws {
        let context = try await loadStudentContext()
        let redirect = "/for-std/change-major-apply/apply?PARENT_URL=/for-std/change-major-apply/index/\(context.studentID)&batchId=\(batchID)&studentId=\(context.studentID)"
        _ = try await formPost("for-std/change-major-apply/cancel", fields: [("batchId", batchID), ("studentId", "\(context.studentID)"), ("applyId", "\(applicationID)"), ("REDIRECT_URL", redirect)])
        do {
            let applications = try await fetchMyTransferApplications(batchID: batchID)
            try Self.requireTransferCancelled(applicationID: applicationID, applications: applications)
        } catch {
            throw AcademicClientError.invalidData("撤销请求已发送，但结果尚未确认：\(error.localizedDescription)")
        }
    }
    static func requireTransferCancelled(applicationID: Int, applications: [TransferMyApply]) throws {
        guard !applications.contains(where: { $0.id == applicationID }) else {
            throw AcademicClientError.invalidData("校方申请列表仍保留此申请")
        }
    }

    func transferDetails(applicationID: Int) async throws -> [AcademicDetailField] {
        let context = try await loadStudentContext()
        let data = try await get("for-std/change-major-apply/info/\(applicationID)", query: [URLQueryItem(name: "studentId", value: "\(context.studentID)")])
        return Self.parseTransferDetails(String(data: data, encoding: .utf8) ?? "")
    }
    static func parseTransferDetails(_ html: String) -> [AcademicDetailField] {
        let document = AcademicHTMLElement.parse(html)
        var fields: [AcademicDetailField] = []
        for row in document.descendants where row.tag == "tr" {
            let cells = row.children.filter { ["th", "td"].contains($0.tag) }.map(\.normalizedText).filter { !$0.isEmpty }
            if cells.count >= 2 { fields.append(.init(label: cells[0], value: cells.dropFirst().joined(separator: " · "))) }
        }
        for box in document.descendants where box.classes.contains("score-box") {
            let score = box.descendants.first { $0.classes.contains("score-text") }?.normalizedText ?? ""
            let rank = box.descendants.first { $0.classes.contains("score-rank") }?.normalizedText ?? ""
            let name = box.descendants.filter { $0.tag == "span" && !$0.classes.contains("score-text") && !$0.classes.contains("score-rank") }.first?.normalizedText ?? "成绩"
            if !score.isEmpty { fields.append(.init(label: name, value: [score, rank].filter { !$0.isEmpty }.joined(separator: " · "))) }
        }
        var seen = Set<String>()
        return fields.filter { seen.insert($0.id).inserted }
    }
}

enum AcademicWorkflowError: LocalizedError {
    case surveyUnconfirmed(String)
    var errorDescription: String? {
        switch self {
        case .surveyUnconfirmed(let detail): return "提交请求已发送，校方结果尚未确认。答卷已保留，可刷新提交状态。\(detail)"
        }
    }
}
