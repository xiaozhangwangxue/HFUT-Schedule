import Foundation

struct AcademicGradeTerm: Codable, Hashable, Identifiable {
    var id: String { term }
    let term: String
    let grades: [AcademicGrade]
}

struct AcademicGrade: Codable, Hashable, Identifiable {
    var id: String { "\(lessonCode)|\(courseName)|\(score)" }
    let courseName: String
    let credits: String
    let gpa: String
    let score: String
    let detail: String
    let lessonCode: String
}

struct AcademicExam: Codable, Hashable, Identifiable {
    var id: String { "\(name)|\(dateTime)" }
    let name: String
    let dateTime: String
    let place: String

    var startDate: Date? {
        UpcomingExamResolver.timing(for: self)?.start
    }

    var endDate: Date? { UpcomingExamResolver.timing(for: self)?.end }
}

struct AcademicRecordsPayload: Codable {
    let grades: [AcademicGradeTerm]
    let exams: [AcademicExam]
}

