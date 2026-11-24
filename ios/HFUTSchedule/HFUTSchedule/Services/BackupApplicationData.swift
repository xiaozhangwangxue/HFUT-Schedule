import Foundation
import ImageIO

/// Portable application data is explicit: no Keychain entries, authentication cookies or bearer tokens.
struct BackupApplicationData: Codable {
    var favorites: [WebFavoriteRecord] = []
    var grades: [AcademicGradeTerm]?
    var exams: [AcademicExam]?
    var student: AcademicStudentInfo?
    var background: Data?
    var storedPreferences: [String: Data] = [:]
    var files: [String: Data] = [:]

    static let preferenceKeys: Set<String> = [
        "specialWorkDayMappingV1", "service-order", "hidden-services", "selectedCampus",
        "electricityDormitoryDefaults.v1.hefei", "electricityDormitoryDefaults.v1.xuancheng", "serviceOrder", "hiddenServices", "serviceCatalogOrderV1", "serviceCatalogHiddenV1",
        "academicReadGradeIDs", "gradeStatisticsDecimalPlaces", "savedShowerDevices", "academicConnectionMode", "aiDeepSeekModel", "readCloudNotificationIDs",
        "electricityDefaultSelectionV1", "electricitySelectedBuilding", "electricitySelectedRoom", "electricityMeterType",
        "schoolNetAccount", "schoolNetOperator", "laundryRegion", "laundryBuilding", "showerDefaultRegion",
        "calendarShowsTimeAxis", "scheduleShowsWeekend", "enableOcrCaptcha", "useDefaultSchoolNetPassword",
        "cloudCommunityImportsV1", "cloudCommunityFilterMatches", "cloudCommunityIncludeExpired", "cloudCommunitySort", "cloudCommunityReverse"
    ]
    static let fileNames: Set<String> = ["source-courses.json", "exam-history.json", "friend-schedules.json"]
    static var applicationDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("HFUTSchedule", isDirectory: true)
    }
    @MainActor static func capture(defaults: UserDefaults = .standard) -> Self {
        let decoder = JSONDecoder()
        var result = Self(favorites: WebFavoriteStore.records(defaults: defaults),
            grades: defaults.data(forKey: "academicGradeTerms").flatMap { try? decoder.decode([AcademicGradeTerm].self, from: $0) },
            exams: defaults.data(forKey: "academicExams").flatMap { try? decoder.decode([AcademicExam].self, from: $0) },
            student: defaults.data(forKey: "academicStudentInfo").flatMap { try? decoder.decode(AcademicStudentInfo.self, from: $0) },
            background: TimetableBackgroundStore.fileURL.flatMap { try? Data(contentsOf: $0) })
        for key in preferenceKeys {
            if let value = defaults.object(forKey: key),
               let data = try? PropertyListSerialization.data(fromPropertyList: ["value": value], format: .binary, options: 0) {
                result.storedPreferences[key] = data
            }
        }
        for name in fileNames {
            if let data = try? Data(contentsOf: applicationDirectory.appendingPathComponent(name)), data.count <= 25_000_000 {
                result.files[name] = data
            }
        }
        return result
    }
    func validate() throws {
        guard favorites.count <= 10_000, favorites.allSatisfy({ item in
            guard let url = URL(string: item.url) else { return false }
            return ["http", "https"].contains(url.scheme?.lowercased() ?? "") && url.host != nil && item.name.count <= 4_096
        }), (grades?.count ?? 0) <= 1_000, (exams?.count ?? 0) <= 100_000,
           storedPreferences.keys.allSatisfy(Self.preferenceKeys.contains), files.keys.allSatisfy(Self.fileNames.contains),
           files.values.reduce(0, { $0 + $1.count }) <= 52_428_800 else { throw CocoaError(.fileReadCorruptFile) }
        if let background {
            guard background.count <= 26_214_400, CGImageSourceCreateWithData(background as CFData, nil) != nil else { throw CocoaError(.fileReadCorruptFile) }
        }
        for data in storedPreferences.values {
            guard data.count <= 2_097_152,
                  let value = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any], value["value"] != nil else { throw CocoaError(.fileReadCorruptFile) }
        }
        for data in files.values { _ = try JSONSerialization.jsonObject(with: data) }
    }
    @MainActor func restore(defaults: UserDefaults = .standard) throws {
        try validate()
        try FileManager.default.createDirectory(at: Self.applicationDirectory, withIntermediateDirectories: true)
        for name in Self.fileNames {
            let url = Self.applicationDirectory.appendingPathComponent(name)
            if let data = files[name] { try data.write(to: url, options: .atomic) }
            else if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
        if let background, let url = TimetableBackgroundStore.fileURL { try background.write(to: url, options: .atomic) }
        else { TimetableBackgroundStore.clear() }
        let oldMapping = defaults.data(forKey: "specialWorkDayMappingV1").flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        for key in oldMapping.keys { if let date = ScheduleCalendar.isoDate(key) { SpecialWorkDayStore.shared.removeTarget(for: date) } }
        for key in Self.preferenceKeys { defaults.removeObject(forKey: key) }
        defaults.set(try JSONEncoder().encode(favorites), forKey: "webNavigationFavoritesV1")
        for (key, data) in storedPreferences {
            let value = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
            defaults.set(value?["value"], forKey: key)
        }
        if let grades { defaults.set(try JSONEncoder().encode(grades), forKey: "academicGradeTerms") }
        if let exams { defaults.set(try JSONEncoder().encode(exams), forKey: "academicExams") }
        if let student { defaults.set(try JSONEncoder().encode(student), forKey: "academicStudentInfo") }
        if let data = storedPreferences["specialWorkDayMappingV1"],
           let box = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
           let bytes = box["value"] as? Data, let mapping = try? JSONDecoder().decode([String: String].self, from: bytes) {
            for (key, target) in mapping { if let date = ScheduleCalendar.isoDate(key) { SpecialWorkDayStore.shared.setTarget(target, for: date) } }
        }
    }
}
