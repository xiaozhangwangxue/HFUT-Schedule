import Foundation
import CryptoKit
import Combine

enum ScheduleSource: String, CaseIterable, Identifiable, Codable {
    case academic, community, uniApp = "uniapp", zhiJian = "zhijian", academicCompact = "jxglstu2"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .academic: "合工大教务"
        case .community: "智慧社区"
        case .uniApp: "合工大教务 UniApp"
        case .zhiJian: "指间工大"
        case .academicCompact: "合工大教务 2"
        }
    }
    var detail: String { self == .community ? "智慧社区课表不支持调休映射" : "使用原平台接口获取课表，并保留离线缓存" }
    var cacheKey: String { rawValue }
}

enum ScheduleSourceParser {
    static func community(_ data: Data) throws -> [Course] {
        let root = try object(data)
        guard let result = root["result"] as? [String: Any], let basics = result["courseBasicInfoDTOList"] as? [[String: Any]] else {
            throw OfficialCampusAPIError.invalidData(root["message"] as? String ?? "社区课表格式无效")
        }
        let startTimes = result["startTime"] as? [String] ?? [], endTimes = result["endTime"] as? [String] ?? []
        let start = (result["start"] as? String).flatMap(ScheduleCalendar.isoDate)
        let courses: [Course] = basics.enumerated().flatMap { index, basic in
            (basic["courseDetailDTOList"] as? [[String: Any]] ?? []).compactMap { detail -> Course? in
                let weekday = integer(detail["week"]), weeks = (detail["weekCount"] as? [Int] ?? []).filter { $0 > 0 }
                let section = integer(detail["section"]), count = max(1, integer(detail["sectionCount"]))
                let clock = (detail["classTime"] as? String ?? "").replacingOccurrences(of: "—", with: "-").replacingOccurrences(of: "~", with: "-").split(separator: "-").map(String.init)
                let from = normalizedClock(clock.count == 2 ? clock[0] : (startTimes.indices.contains(section - 1) ? startTimes[section - 1] : ""))
                let to = normalizedClock(clock.count == 2 ? clock[1] : (endTimes.indices.contains(section + count - 2) ? endTimes[section + count - 2] : ""))
                guard (1...7).contains(weekday), from.contains(":"), to.contains(":"), let name = basic["courseName"] as? String else { return nil }
                let room = detail["place"] as? String ?? "", teacher = detail["teacher"] as? String ?? ""
                let dates = start.map { date in weeks.compactMap { ScheduleCalendar.calendar.date(byAdding: .day, value: ($0 - 1) * 7 + weekday - 1, to: date).map(HolidayCalendarStore.key) } }
                return Course(id: stableID("community|\(basic["courseId"] ?? name)|\(weekday)|\(from)|\(to)|\(room)|\(teacher)"),
                    name: name, teacher: teacher, location: room, weekday: weekday, startTime: from, endTime: to,
                    colorIndex: index % 5, weekIndices: weeks, dates: dates, source: "community",
                    details: CourseDetails(type: basic["trainingCategoryName_dictText"] as? String, credits: basic["credit"] as? Double,
                        code: basic["courseId"] as? String, className: basic["className"] as? String))
            }
        }
        var grouped: [UUID: Course] = [:]
        for course in courses {
            if var previous = grouped[course.id] {
                previous.weekIndices = Array(Set((previous.weekIndices ?? []) + (course.weekIndices ?? []))).sorted()
                if previous.dates != nil || course.dates != nil { previous.dates = Array(Set((previous.dates ?? []) + (course.dates ?? []))).sorted() }
                grouped[course.id] = previous
            } else { grouped[course.id] = course }
        }
        return grouped.values.sorted { $0.weekday == $1.weekday ? $0.startTime < $1.startTime : $0.weekday < $1.weekday }
    }

    static func uniApp(_ data: Data) throws -> [Course] {
        let root = try object(data)
        guard let lessons = root["data"] as? [[String: Any]] else { throw OfficialCampusAPIError.invalidData("UniApp课表格式无效") }
        var grouped: [UUID: Course] = [:]
        for (index, lesson) in lessons.enumerated() {
            let base = lesson["course"] as? [String: Any] ?? [:]
            for item in lesson["schedules"] as? [[String: Any]] ?? [] {
                let weekday = integer(item["weekday"]), from = clock(integer(item["startTime"])), to = clock(integer(item["endTime"]))
                let room = (item["room"] as? [String: Any])?["nameZh"] as? String ?? ""
                let teacher = item["teacherName"] as? String ?? "", name = base["nameZh"] as? String ?? ""
                guard !name.isEmpty, (1...7).contains(weekday) else { continue }
                let id = stableID("uniapp|\(lesson["id"] ?? "")|\(weekday)|\(from)|\(to)|\(room)|\(teacher)")
                var course = grouped[id] ?? Course(id: id, name: name, teacher: teacher, location: room, weekday: weekday,
                    startTime: from, endTime: to, colorIndex: index % 5, weekIndices: [], dates: [], source: "uniapp",
                    details: CourseDetails(lessonID: integer(lesson["id"]), type: (lesson["courseType"] as? [String: Any])?["nameZh"] as? String,
                        classmatesCount: integer(lesson["stdCount"]), credits: base["credits"] as? Double,
                        department: (lesson["openDepartment"] as? [String: Any])?["nameZh"] as? String,
                        code: lesson["code"] as? String, remark: lesson["remark"] as? String))
                if let date = item["date"] as? String { course.dates = Array(Set((course.dates ?? []) + [date])).sorted() }
                let week = integer(item["weekIndex"])
                if week > 0 { course.weekIndices = Array(Set((course.weekIndices ?? []) + [week])).sorted() }
                grouped[id] = course
            }
        }
        return grouped.values.sorted { $0.weekday == $1.weekday ? $0.startTime < $1.startTime : $0.weekday < $1.weekday }
    }

    static func stableID(_ key: String) -> UUID {
        let bytes = Array(SHA256.hash(data: Data(key.utf8)).prefix(16))
        return UUID(uuid: (bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15]))
    }
    static func integer(_ value: Any?) -> Int { (value as? Int) ?? Int(value as? String ?? "") ?? 0 }
    static func normalizedClock(_ raw: String) -> String {
        let values = raw.split(separator: ":").compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard values.count == 2, (0...24).contains(values[0]), (0...59).contains(values[1]) else { return "" }
        return String(format: "%02d:%02d", values[0], values[1])
    }
    private static func clock(_ value: Int) -> String { String(format: "%02d:%02d", value / 100, value % 100) }
    static func object(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw OfficialCampusAPIError.invalidResponse }
        return value
    }
}

@MainActor
final class ScheduleSourceCoordinator: ObservableObject {
    static let shared = ScheduleSourceCoordinator()
    @Published private(set) var isLoading = false
    @Published private(set) var message: String?
    @Published private(set) var friendID: String?
    private var activeKey = "academic"
    private var cached: [String: [Course]] = [:]
    private var generation = UUID()
    private var restored = false
    private let cacheURL: URL

    init(cacheURL: URL? = nil) {
        self.cacheURL = cacheURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HFUTSchedule/source-courses.json")
        if let data = try? Data(contentsOf: self.cacheURL), let archive = try? JSONDecoder().decode(Archive.self, from: data) {
            activeKey = archive.activeKey; cached = archive.courses; friendID = archive.friendID
        }
    }

    func activate(_ source: ScheduleSource, store: ScheduleStore, friend: String? = nil) {
        guard !store.requiresRecovery else { message = store.storageError; return }
        let key = friend.map { "friend:\($0)" } ?? source.cacheKey
        if !restored {
            restored = true
            if let saved = cached[activeKey] {
                guard store.replace(with: store.courses.filter { $0.source == nil } + saved) else { message = store.storageError; return }
            }
        }
        guard activeKey != key else { return }
        generation = UUID(); isLoading = false
        cached[activeKey] = store.courses.filter { $0.source != nil }
        let local = store.courses.filter { $0.source == nil }
        guard store.replace(with: local + (cached[key] ?? [])) else { message = store.storageError; return }
        activeKey = key; friendID = friend
        UserDefaults.standard.set(source.rawValue, forKey: AppSettingsKey.defaultCourseSource)
        persist()
        message = cached[key] == nil ? "尚无该来源的离线课表，请刷新获取。" : nil
    }

    func cacheAcademic(_ courses: [Course]) { cached["academic"] = courses; persist() }

    func reloadAfterBackup(store: ScheduleStore) {
        generation = UUID(); isLoading = false; restored = false
        if let data = try? Data(contentsOf: cacheURL), let archive = try? JSONDecoder().decode(Archive.self, from: data) {
            activeKey = archive.activeKey; cached = archive.courses; friendID = archive.friendID
        } else {
            activeKey = ScheduleSource(rawValue: UserDefaults.standard.string(forKey: AppSettingsKey.defaultCourseSource) ?? "academic")?.cacheKey ?? "academic"
            cached = [activeKey:store.courses.filter { $0.source != nil }]; friendID = nil
        }
        let source = ScheduleSource(rawValue: UserDefaults.standard.string(forKey: AppSettingsKey.defaultCourseSource) ?? "academic") ?? .academic
        activate(source, store: store, friend: source == .community ? friendID : nil)
    }

    func refresh(_ source: ScheduleSource, store: ScheduleStore, weekStarting: Date? = nil) async {
        guard !isLoading || source == .zhiJian else { return }
        let request = UUID(); generation = request; let requestedKey = activeKey
        isLoading = true; message = nil
        defer { if generation == request { isLoading = false } }
        do {
            let courses: [Course]
            switch source {
            case .community:
                let suffix = friendID.map { "?username=\($0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" } ?? ""
                courses = try ScheduleSourceParser.community(await OfficialCampusAPIClient.shared.communityAuthorizedData(path: "api/business/coursearrangement/listselect" + suffix))
            case .uniApp:
                courses = try ScheduleSourceParser.uniApp(await OfficialCampusAPIClient.shared.uniAppAuthorizedData(path: "eams-micro-server/api/v1/lesson/student/course-table/\(AcademicPortal.currentSemesterID)"))
            case .academic:
                let mode = AcademicConnectionMode(rawValue: UserDefaults.standard.string(forKey: "academicConnectionMode") ?? "direct") ?? .direct
                courses = try await AcademicClient(mode: mode, cookies: CampusSessionStore.shared.allCookies).fetchSchedule(semesterID: AcademicPortal.currentSemesterID).courses()
            case .academicCompact:
                let mode = AcademicConnectionMode(rawValue: UserDefaults.standard.string(forKey: "academicConnectionMode") ?? "direct") ?? .direct
                courses = try await AcademicClient(mode: mode, cookies: CampusSessionStore.shared.allCookies).lessonScheduleCourses(semesterID: AcademicPortal.currentSemesterID)
            case .zhiJian:
                let monday = weekStarting ?? ScheduleCalendar.calendar.dateInterval(of: .weekOfYear, for: Date())!.start
                let studentID = AcademicStudentStore().info?.studentID ?? ""
                guard !studentID.isEmpty else { throw OfficialCampusAPIError.invalidData("请先登录并同步学籍，以取得指间课表所需学号") }
                let fetched = try await ZhiJianScheduleClient().courses(studentID: studentID, monday: monday)
                let sunday = ScheduleCalendar.calendar.date(byAdding: .day, value: 7, to: monday) ?? monday
                let from = HolidayCalendarStore.key(for: monday), to = HolidayCalendarStore.key(for: sunday)
                let otherWeeks = (cached[requestedKey] ?? []).compactMap { item -> Course? in
                    var item = item
                    item.dates = item.dates?.filter { $0 < from || $0 >= to }
                    return item.dates?.isEmpty == false ? item : nil
                }
                courses = otherWeeks + fetched
            }
            guard !Task.isCancelled, generation == request, activeKey == requestedKey else { return }
            let local = store.courses.filter { $0.source == nil }
            guard store.replace(with: local + courses) else { message = store.storageError; return }
            cached[requestedKey] = courses; persist()
            message = "已更新 \(courses.count) 个课程时段"
        } catch {
            PlatformDiagnosticsStore.shared.record(context: "课表数据源同步", error: error)
            if generation == request { message = error.localizedDescription }
        }
    }

    private struct Archive: Codable { let activeKey: String; let courses: [String: [Course]]; let friendID: String? }
    private func persist() {
        do {
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(Archive(activeKey: activeKey, courses: cached, friendID: friendID)).write(to: cacheURL, options: .atomic)
        } catch {
            PlatformDiagnosticsStore.shared.record(context: "课表来源缓存保存", error: error)
            message = "来源缓存保存失败：\(error.localizedDescription)"
        }
    }
}

struct ZhiJianScheduleClient {
    private let session: URLSession
    init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = .shared
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
    }

    func courses(studentID: String, monday: Date) async throws -> [Course] {
        let base = "https://zjgd.hfut.edu.cn:8181/"
        var entry = URLComponents(string: base + "wui/cas-entrance.jsp")!
        entry.queryItems = [URLQueryItem(name: "path", value: base + "wui/index.html#/main"), URLQueryItem(name: "ssoType", value: "CAS")]
        var login = URLComponents(string: "https://cas.hfut.edu.cn/cas/login")!
        login.queryItems = [URLQueryItem(name: "service", value: entry.url!.absoluteString)]
        _ = try await session.data(from: login.url!)
        let params = try JSONSerialization.data(withJSONObject: ["date": HolidayCalendarStore.key(for: monday), "id_number": studentID])
        var endpoint = URLComponents(string: base + "api/esb/oa/execute/TB_KBSJCL")!
        endpoint.queryItems = [URLQueryItem(name: "params", value: String(decoding: params, as: UTF8.self))]
        var request = URLRequest(url: endpoint.url!); request.httpMethod = "POST"
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw OfficialCampusAPIError.invalidResponse }
        let envelope = try ScheduleSourceParser.object(data)
        guard let raw = (envelope["data"] as? [String: Any])?["rawdata"] as? String,
              let rows = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [[String: Any]] else {
            throw OfficialCampusAPIError.invalidData(envelope["msg"] as? String ?? "指间工大会话未生效，请重新完成统一身份认证")
        }
        let overview = try await CampusExtraAPIClient.shared.fetchTermOverview()
        CampusSessionStore.shared.persist(HTTPCookieStorage.shared.cookies ?? [])
        return Self.parse(rows, monday: monday, starts: overview.startTimes, ends: overview.endTimes)
    }

    static func parse(_ rows: [[String: Any]], monday: Date, starts: [String], ends: [String]) -> [Course] {
        let nextWeek = ScheduleCalendar.calendar.date(byAdding: .day, value: 7, to: monday) ?? monday
        return rows.enumerated().compactMap { index, item in
            guard let name = item["kcmc"] as? String, let day = item["skrq"] as? String,
                  let date = ScheduleCalendar.isoDate(day), date >= monday, date < nextWeek else { return nil }
            let start = ScheduleSourceParser.integer(item["skjc"]), count = ScheduleSourceParser.integer(item["cxjc"])
            guard starts.indices.contains(start - 1), ends.indices.contains(start + count - 2), count > 0 else { return nil }
            let weekday = FocusPlanResolver.weekday(for: date)
            return Course(id: ScheduleSourceParser.stableID("zhijian|\(item["kxh"] ?? name)|\(day)|\(start)"),
                name: name, teacher: item["jsxm"] as? String ?? "", location: item["jxdd"] as? String ?? "",
                weekday: weekday, startTime: starts[start - 1], endTime: ends[start + count - 2], colorIndex: index % 5,
                weekIndices: nil, dates: [day], source: "zhijian",
                details: CourseDetails(type: item["kclx"] as? String, department: item["skbm"] as? String,
                    code: item["kxh"] as? String, className: item["jxbdm"] as? String,
                    scheduleText: "第\(start)–\(start + count - 1)节"))
        }
    }
}
