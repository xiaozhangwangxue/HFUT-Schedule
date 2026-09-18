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
        let start = String(dateTime.prefix(16))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: start)
    }
}

struct AcademicRecordsPayload: Codable {
    let grades: [AcademicGradeTerm]
    let exams: [AcademicExam]
}

