import Foundation
import SQLite3

/// Maps portable Android data to iOS models; Android credentials and executable/platform files are ignored.
enum AndroidBackupImporter {
    static func decode(_ data: Data) throws -> ScheduleBackupPayload {
        let entries = try PortableZIPReader.entries(data)
        var values: [String: Any] = [:]
        for (name, data) in entries where name.hasPrefix("shared_prefs/") && name.hasSuffix(".xml") {
            let delegate = AndroidXMLPreferences(); let parser = XMLParser(data: data); parser.delegate = delegate; parser.shouldResolveExternalEntities = false
            if parser.parse() { values.merge(delegate.values, uniquingKeysWith: { first, _ in first }) }
        }
        for (name, data) in entries where name.hasSuffix(".preferences_pb") {
            for field in try ProtoFields.read(data) where field.number == 1 {
                let fields = try ProtoFields.read(field.bytes)
                guard let key = fields.first(where: { $0.number == 1 }).flatMap({ String(data: $0.bytes, encoding: .utf8) }),
                      let boxed = fields.first(where: { $0.number == 2 }), let value = try ProtoFields.read(boxed.bytes).first else { continue }
                switch value.number {
                case 1: values[key] = value.integer != 0
                case 2: values[key] = Double(Float(bitPattern: UInt32(truncatingIfNeeded: value.integer)))
                case 3, 4: values[key] = Double(Int64(bitPattern: value.integer))
                case 5: values[key] = String(data: value.bytes, encoding: .utf8)
                case 7: values[key] = Double(bitPattern: value.integer)
                default: break
                }
            }
        }
        func cache(_ prefix: String) -> Data? {
            entries.keys.filter { $0.hasPrefix("files/data_cache/\(prefix)") && $0.hasSuffix(".cache") }
                .sorted { $0.localizedStandardCompare($1) == .orderedDescending }.first.flatMap { entries[$0] }
        }
        var courses: [Course] = []
        if let datumData = cache("datum_") ?? cache("datum.") ?? (values["json"] as? String).map({ Data($0.utf8) }),
           let datum = try? JSONDecoder().decode(AcademicDatumResponse.self, from: datumData) {
            let termData = cache("courses_") ?? (values["courses"] as? String).map({ Data($0.utf8) })
            let term = termData.flatMap { try? JSONDecoder().decode(AcademicTermResponse.self, from: $0) }
                ?? AcademicTermResponse(lessonIds: datum.result.lessonList.compactMap { Int($0.id) }, lessons: datum.result.lessonList, timeTableLayoutId: nil, currentWeek: nil)
            courses = AcademicSyncPayload(term: term, datum: datum).courses()
        }
        if courses.isEmpty, let raw = cache("uni_app_courses_") { courses = (try? ScheduleSourceParser.uniApp(raw)) ?? [] }
        if courses.isEmpty, let raw = cache("community_courses") { courses = (try? ScheduleSourceParser.community(raw)) ?? [] }
        var appData = BackupApplicationData()
        if let html = (cache("grade") ?? (values["grade"] as? String).map { Data($0.utf8) }).flatMap({ String(data: $0, encoding: .utf8) }) {
            let grades = AcademicHTMLParser.grades(from: html)
            if !grades.isEmpty { appData.grades = grades }
        }
        if let html = (cache("exam") ?? (values["examJXGLSTU"] as? String).map { Data($0.utf8) }).flatMap({ String(data: $0, encoding: .utf8) }) {
            let exams = AcademicHTMLParser.exams(from: html)
            if !exams.isEmpty { appData.exams = exams }
        }
        let infoHTML = cache("jxglstu_info").flatMap { String(data: $0, encoding: .utf8) } ?? values["info"] as? String ?? ""
        let profileHTML = cache("jxglstu_profile").flatMap { String(data: $0, encoding: .utf8) } ?? values["profile"] as? String ?? ""
        if !infoHTML.isEmpty {
            let info = AcademicHTMLParser.studentInfo(from: infoHTML, profileHTML: profileHTML, fallbackStudentID: "")
            if !info.studentID.isEmpty { appData.student = info }
        }
        if appData.exams == nil, let data = cache("uni_app_exams"),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let rows = object["data"] as? [[String: Any]] {
            appData.exams = rows.compactMap { row in
                guard let name = row["courseNameZh"] as? String, let date = row["examDate"] as? String else { return nil }
                func clock(_ value: Any?) -> String {
                    let raw = (value as? NSNumber)?.intValue ?? Int(value as? String ?? "") ?? 0
                    return String(format: "%02d:%02d", raw / 100, raw % 100)
                }
                return AcademicExam(name: name, dateTime: "\(date) \(clock(row["startTime"]))~\(clock(row["endTime"]))", place: row["place"] as? String ?? "")
            }
        }
        var events: [CustomEvent] = []
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("android-backup-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for (name, bytes) in entries where name.hasPrefix("databases/") && name.split(separator: "/").count == 2 {
            try bytes.write(to: directory.appendingPathComponent(URL(fileURLWithPath: name).lastPathComponent), options: .atomic)
        }
        var mapping: [String: String] = [:]
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            guard (try? Data(contentsOf: file).prefix(16)) == Data("SQLite format 3\0".utf8) else { continue }
            var database: OpaquePointer?
            guard sqlite3_open_v2(file.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { sqlite3_close(database); continue }
            defer { sqlite3_close(database) }
            for row in rows("SELECT * FROM event LIMIT 100000", database) {
                guard let title = row["title"] as? String, let start = row["start_time"] as? Double, let end = row["end_time"] as? Double else { continue }
                let item = CustomEvent(title: title, detail: row["description"] as? String ?? "", location: row["remark"] as? String ?? "",
                    start: Date(timeIntervalSince1970: start / 1000), end: Date(timeIntervalSince1970: end / 1000),
                    kind: row["type"] as? String == "NET_COURSE" ? .deadline : .event, groupID: row["group_id"] as? String)
                if item.isValid { events.append(item) }
            }
            for row in rows("SELECT name,url FROM web_url LIMIT 10000", database) {
                guard let name = row["name"] as? String, let text = row["url"] as? String,
                      let url = URL(string: text), ["http", "https"].contains(url.scheme ?? ""), url.host != nil else { continue }
                if !appData.favorites.contains(where: { $0.url == text }) { appData.favorites.append(WebFavoriteRecord(name: name, url: text)) }
            }
            for row in rows("SELECT origin_date,target_date FROM special_work_day LIMIT 10000", database) {
                if let origin = row["origin_date"] as? String, let target = row["target_date"] as? String,
                   ScheduleCalendar.isoDate(origin) != nil, ScheduleCalendar.isoDate(target) != nil { mapping[origin] = target }
            }
        }
        if !mapping.isEmpty {
            appData.storedPreferences["specialWorkDayMappingV1"] = try PropertyListSerialization.data(fromPropertyList: ["value": JSONEncoder().encode(mapping)], format: .binary, options: 0)
        }
        var preferences = mappedPreferences(values)
        if let source = courses.first?.source, ScheduleSource(rawValue: source) != nil { preferences[AppSettingsKey.defaultCourseSource] = .string(source) }
        guard !courses.isEmpty || !events.isEmpty || !appData.favorites.isEmpty || !preferences.isEmpty || appData.student != nil || appData.grades != nil || appData.exams != nil else {
            throw AndroidBackupError.noPortableData
        }
        try appData.validate()
        return ScheduleBackupPayload(courses: courses, events: events, preferences: preferences, applicationData: appData,
            importSummary: "已迁移 Android 备份中的 \(courses.count) 个课程时段、\(events.count) 项日程、\(appData.favorites.count) 个收藏及兼容的外观/偏好。Android 认证会话和系统专属数据需要在 iOS 重新配置。")
    }

    private static func rows(_ sql: String, _ database: OpaquePointer?) -> [[String: Any]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        var result: [[String: Any]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: Any] = [:]
            for column in 0..<sqlite3_column_count(statement) {
                let key = String(cString: sqlite3_column_name(statement, column))
                switch sqlite3_column_type(statement, column) {
                case SQLITE_INTEGER, SQLITE_FLOAT: row[key] = sqlite3_column_double(statement, column)
                case SQLITE_TEXT: if let text = sqlite3_column_text(statement, column) { row[key] = String(cString: text) }
                default: break
                }
            }
            result.append(row)
        }
        return result
    }
    private static func mappedPreferences(_ source: [String: Any]) -> [String: BackupPreference] {
        let bools = ["pure_dark": AppSettingsKey.pureBlack, "web_view_dark": AppSettingsKey.webDarkMode,
            "liquid_glass": AppSettingsKey.liquidGlass, "haze_blur_4": AppSettingsKey.layerBlur,
            "show_bottom_bar_label": AppSettingsKey.showAllTabLabels, "merge_square": AppSettingsKey.mergeConflictingSquares,
            "auto_term": AppSettingsKey.autoTermStart, "show_overdue_focus": AppSettingsKey.showFinishedToday,
            "show_focus_electric": AppSettingsKey.focusShowsElectric, "show_focus_school_net": AppSettingsKey.focusShowsNetwork,
            "show_focus_school_card": AppSettingsKey.focusShowsCard, "show_focus_today": AppSettingsKey.focusShowsTomorrow,
            "focus_show_weather_warn": AppSettingsKey.focusShowsWeather, "ignore_unjoined_grade_items": AppSettingsKey.ignoreExcludedGrades,
            "container_share": AppSettingsKey.sharedContainer]
        var result: [String: BackupPreference] = [:]
        for (old, new) in bools { if let value = source[old] as? Bool { result[new] = .bool(value) } }
        let numbers = ["max_flow": AppSettingsKey.xuanchengQuota, "auto_term_value": AppSettingsKey.manualSemesterID,
            "custom_calendar_square_alpha": AppSettingsKey.calendarOpacity, "custom_calendar_square_blur": AppSettingsKey.backgroundBlur,
            "shared_nav_speed_radio": AppSettingsKey.transitionSpeed, "focus_school_card_quick_button": AppSettingsKey.focusCardAction]
        for (old, new) in numbers { if let value = source[old] as? NSNumber { result[new] = .number(value.doubleValue) } }
        if let mode = (source["color_mode"] as? NSNumber)?.intValue { result[AppSettingsKey.appearance] = .string(mode == 1 ? "light" : mode == 2 ? "dark" : "auto") }
        if let mode = (source["calendar_show_teacher_2"] as? NSNumber)?.intValue { result[AppSettingsKey.teacherDisplayMode] = .number(mode == 0 ? 1 : mode == 1 ? 2 : 0) }
        if let mode = (source["custom_color_style_2"] as? NSNumber)?.intValue { result[AppSettingsKey.colorStyle] = .string(mode == 0 ? "monochrome" : mode == 1 ? "subtle" : mode == 3 ? "vibrant" : "normal") }
        if let color = source["custom_color"] as? NSNumber, color.int64Value >= 0 { result[AppSettingsKey.accentHex] = .string(String(format: "%06X", color.uint64Value & 0xffffff)) }
        if let mode = source["new_bottom_bar"] as? Bool { result[AppSettingsKey.bottomBarStyle] = .string(mode ? "floating" : "system") }
        return BackupPreferences.normalized(result)
    }
}

enum AndroidBackupError: LocalizedError {
    case noPortableData
    var errorDescription: String? { "ZIP 中没有找到可迁移的课程、日程、收藏或偏好；未修改现有数据" }
}

private final class AndroidXMLPreferences: NSObject, XMLParserDelegate {
    var values: [String: Any] = [:]
    private var key: String?, content = "", kind = ""
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        kind = elementName; key = attributes["name"]; content = ""
        if let key, let value = attributes["value"] {
            if elementName == "boolean" { values[key] = value == "true" }
            else if let number = Double(value) { values[key] = number }
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { content += string }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { content += String(data: CDATABlock, encoding: .utf8) ?? "" }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if elementName == "string", let key { values[key] = content }; key = nil
    }
}

private enum ProtoFields {
    struct Field { let number: Int; let bytes: Data; let integer: UInt64 }
    static func read(_ data: Data) throws -> [Field] {
        let input = [UInt8](data); var cursor = 0; var result: [Field] = []
        func varint() throws -> UInt64 {
            var value: UInt64 = 0
            for shift in stride(from: 0, through: 63, by: 7) {
                guard cursor < input.count else { throw CocoaError(.fileReadCorruptFile) }
                let byte = input[cursor]; cursor += 1
                if shift == 63 && byte > 1 { throw CocoaError(.fileReadCorruptFile) }
                value |= UInt64(byte & 0x7f) << shift
                if byte & 0x80 == 0 { return value }
            }
            throw CocoaError(.fileReadCorruptFile)
        }
        while cursor < input.count {
            let tag = try varint(), field = Int(tag >> 3), wire = tag & 7
            guard field > 0, result.count < 100_000 else { throw CocoaError(.fileReadCorruptFile) }
            if wire == 0 { result.append(Field(number: field, bytes: Data(), integer: try varint())); continue }
            let length: Int
            if wire == 2 { let raw = try varint(); guard raw <= UInt64(input.count) else { throw CocoaError(.fileReadCorruptFile) }; length = Int(raw) }
            else if wire == 5 { length = 4 } else if wire == 1 { length = 8 } else { throw CocoaError(.fileReadCorruptFile) }
            guard cursor + length <= input.count else { throw CocoaError(.fileReadCorruptFile) }
            let bytes = Data(input[cursor..<(cursor + length)]); cursor += length
            let integer = wire == 2 ? 0 : bytes.enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << ($1.offset * 8) }
            result.append(Field(number: field, bytes: bytes, integer: integer))
        }
        return result
    }
}
