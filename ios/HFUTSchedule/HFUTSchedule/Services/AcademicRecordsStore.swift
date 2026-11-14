import Foundation

@MainActor
final class AcademicRecordsStore: ObservableObject {
    @Published private(set) var gradeTerms: [AcademicGradeTerm] = []
    @Published private(set) var exams: [AcademicExam] = []

    private let gradesKey = "academicGradeTerms"
    private let examsKey = "academicExams"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: gradesKey),
           let decoded = try? JSONDecoder().decode([AcademicGradeTerm].self, from: data) {
            gradeTerms = decoded
        }
        if let data = defaults.data(forKey: examsKey),
           let decoded = try? JSONDecoder().decode([AcademicExam].self, from: data) {
            exams = decoded
        }
    }

    func replaceGrades(with terms: [AcademicGradeTerm]) {
        gradeTerms = terms
        persist(terms, key: gradesKey)
    }

    func replaceExams(with newExams: [AcademicExam]) {
        exams = newExams.sorted {
            ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture)
        }
        persist(exams, key: examsKey)
    }

    private func persist<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}

