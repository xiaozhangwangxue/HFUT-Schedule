import Foundation

@MainActor
final class AcademicRecordsStore: ObservableObject {
    @Published private(set) var gradeTerms: [AcademicGradeTerm] = []
    @Published private(set) var exams: [AcademicExam] = []
    @Published private(set) var newGradeCount = 0
    private let readGradesKey = "academicReadGradeIDs"
    private var readGradeIDs: Set<String>?

    private let gradesKey = "academicGradeTerms"
    private let examsKey = "academicExams"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: gradesKey),
           let decoded = try? JSONDecoder().decode([AcademicGradeTerm].self, from: data) {
            gradeTerms = decoded
        }
        if let saved = defaults.stringArray(forKey: readGradesKey) {
            readGradeIDs = Set(saved)
            newGradeCount = Self.gradeIDs(gradeTerms).subtracting(readGradeIDs ?? []).count
        } else if !gradeTerms.isEmpty {
            readGradeIDs = Self.gradeIDs(gradeTerms)
            defaults.set(Array(readGradeIDs ?? []), forKey: readGradesKey)
        }
        if let data = defaults.data(forKey: examsKey),
           let decoded = try? JSONDecoder().decode([AcademicExam].self, from: data) {
            exams = decoded
        }
    }

    func replaceGrades(with terms: [AcademicGradeTerm]) {
        let ids = Self.gradeIDs(terms)
        if let readGradeIDs { newGradeCount = ids.subtracting(readGradeIDs).count }
        else if !terms.isEmpty {
            readGradeIDs = ids
            defaults.set(Array(ids), forKey: readGradesKey)
            newGradeCount = 0
        }
        gradeTerms = terms
        persist(terms, key: gradesKey)
    }

    func markGradesRead() {
        guard !gradeTerms.isEmpty || readGradeIDs != nil else { return }
        readGradeIDs = Self.gradeIDs(gradeTerms)
        defaults.set(Array(readGradeIDs ?? []), forKey: readGradesKey)
        newGradeCount = 0
    }

    private static func gradeIDs(_ terms: [AcademicGradeTerm]) -> Set<String> {
        Set(terms.flatMap { term in term.grades.map { "\(term.id)|\($0.id)" } })
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

