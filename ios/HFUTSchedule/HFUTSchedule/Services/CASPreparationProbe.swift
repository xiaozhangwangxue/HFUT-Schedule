#if DEBUG
import Foundation
import UIKit
import SwiftUI

/// Opt-in, GET-only device diagnostic. Never records cookie values, credentials,
/// request bodies, response bodies, service tickets, or URL query strings.
enum CASPreparationProbe {
    private static let lock = NSLock()
    private static var active = false
    private static var recordsTransport = true
    private static var entries: [[String: Any]] = []
    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CASPreparationDiagnostics.json")
    }
    private static func save() {
        let envelope: [String: Any] = ["system": ProcessInfo.processInfo.operatingSystemVersionString, "entries": entries]
        if let data = try? JSONSerialization.data(withJSONObject: envelope, options: [.prettyPrinted,.sortedKeys]) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
    private static func begin(transport: Bool = true) { lock.lock(); defer { lock.unlock() }; active = true; recordsTransport = transport; entries = []; save() }
    private static func append(_ entry: [String: Any]) {
        lock.lock(); defer { lock.unlock() }
        guard active else { return }
        entries.append(entry); save()
    }
    static func record(_ request: URLRequest, _ response: HTTPURLResponse, _ data: Data) {
        lock.lock(); let allowed = active && recordsTransport; lock.unlock()
        guard allowed else { return }
        guard request.httpMethod == nil || request.httpMethod == "GET" else { return }
        let headerValues = CASCookieParser.headerValues(from: response)
        let raw = headerValues.joined(separator:"\n")
        let text = String(data:data,encoding:.utf8) ?? ""
        let json = (try? JSONSerialization.jsonObject(with:data)) as? [String: Any]
        append([
            "host": request.url?.host ?? "", "path": request.url?.path ?? "", "status":response.statusCode,
            "headerNames":response.allHeaderFields.keys.map { String(describing:$0) }.sorted(),
            "setCookieFields":headerValues.count, "setCookieLengths":headerValues.map(\.utf8.count),
            "setCookieValueType":response.allHeaderFields.first { String(describing:$0.key).lowercased() == "set-cookie" }.map { String(reflecting:type(of:$0.value)) } ?? "absent",
            "rawHeaderHasKeyName":raw.contains("LOGIN_FLAVORING"),
            "parsedCookieNames":CASCookieParser.cookies(from:response).map(\.name),
            "rawKeyLength":CASCookieParser.value(named:"LOGIN_FLAVORING",in:response)?.utf8.count ?? 0,
            "bodyBytes":data.count, "bodyHasKeyName":text.contains("LOGIN_FLAVORING"),
            "virtualKeyLength":CASCookieParser.virtualValue(named:"LOGIN_FLAVORING",data:data)?.utf8.count ?? 0,
            "jsonKeys":json?.keys.sorted() ?? [],
            "jsonDataKeys":(json?["data"] as? [String:Any])?.keys.sorted() ?? [],
            "loginFormPresent":text.contains("name=\"execution\"") || text.contains("name='execution'"),
            "requestCookieNames":(request.value(forHTTPHeaderField:"Cookie") ?? "").split(separator:";").map { String($0.split(separator:"=",maxSplits:1).first ?? "").trimmingCharacters(in:.whitespaces) }
        ])
    }
    static func recordProfileShape(_ root: [String: Any], studentID: String) {
        let user = root["user"] as? [String: Any] ?? [:]
        append(["service": "profilePhoneShape", "rootKeys": root.keys.sorted(), "userKeys": user.keys.sorted(),
            "studentNumberMatches": ["sno", "studentId", "account"].contains { String(describing: user[$0] ?? "") == studentID },
            "phoneNormalizable": StudentPhone.normalized(user["phoneNumber"] as? String) != nil])
    }
    static func run() async {
        begin()
        for mode in AcademicConnectionMode.allCases {
            append(["mode":mode.rawValue,"phase":"start"])
            do {
                let result = try await CASLoginClient(mode:mode).prepare(includeCaptcha:false)
                append(["mode":mode.rawValue,"phase":"success","executionPresent":!result.execution.isEmpty,"needsCaptcha":result.needsCaptcha])
            } catch {
                append(["mode":mode.rawValue,"phase":"failed","error":String(describing:type(of:error)),"message":error.localizedDescription])
            }
        }
        lock.lock(); active = false; lock.unlock()
    }
    /// Opt-in read-only account checks. No add/drop, payment, password login or
    /// account values are recorded. POST is used only by official query APIs.
    @MainActor static func runFunctions() async {
        begin(transport: false)
        let mode = AcademicConnectionMode(rawValue: UserDefaults.standard.string(forKey: "academicConnectionMode") ?? "") ?? .direct
        let client = AcademicClient(mode: mode, cookies: CampusSessionStore.shared.allCookies)
        var student: AcademicStudentInfo?
        await check("studentInfo") {
            let value = try await client.fetchStudentInfo(); student = value
            return ["fields": value.fields.count, "fieldNames": value.fields.keys.sorted(), "phoneAvailable": StudentPhone.from(value) != nil, "phoneTextLength": value.fields["手机"]?.count ?? 0, "phoneDigitCount": value.fields["手机"]?.filter(\.isNumber).count ?? 0, "publicStudentIDAvailable": !value.studentID.isEmpty]
        }
        await check("termCourses") {
            let rows = try await client.fetchTermCourses(semesterID: AcademicPortal.currentSemesterID)
            return ["count": rows.count, "textbookAvailable": rows.first?.textbookNotice == nil]
        }
        await check("cardBills") {
            let page = try await CampusServiceClient.shared.fetchCampusCardBills()
            return ["count": page.records.count, "total": page.total]
        }
        await check("cardAnalysis") {
            let bills = try await CampusServiceClient.shared.fetchAllCampusCardBills()
            let analysis = CampusCardAnalysis.forecast(bills)
            return ["bills": bills.count, "days": analysis.dailyAmounts.count, "merchants": analysis.merchants.count]
        }
        await check("courseSelection") {
            let turns = try await client.fetchCourseSelectionTurns()
            var total = 0
            if let turn = turns.first { total = try await client.fetchSelectableLessons(turnID: turn.id).count }
            return ["turns": turns.count, "firstTurnLessons": total]
        }
        if let student {
            await check("campusMail") {
                let url = try await CampusServiceClient.shared.fetchCampusMailURL(email: "\(student.studentID)@mail.hfut.edu.cn", forceRefresh: true)
                return ["linkAvailable": url != nil]
            }
        }
        var officialPhone: String?
        if let student { officialPhone = try? await CampusServiceClient.shared.fetchProfilePhone(studentID: student.studentID) }
        append(["service": "profilePhone", "phase": officialPhone == nil ? "unavailable" : "success"])
        let studentStore = AcademicStudentStore()
        if let student { studentStore.replace(with: student) }
        let phone = await studentStore.phoneForLifeServices()
        append(["service": "automaticPhone", "phase": phone == nil ? "unavailable" : "success", "source": studentStore.lifeServicePhoneSource ?? "unavailable"])
        if let phone {
            await check("bathingBalance") {
                let kind: HuiXinFeeKind = UserDefaults.standard.string(forKey: "selectedCampus") == "xuancheng" ? .bathingXuancheng(phone: phone) : .bathingHefei(phone: phone)
                let rows = try await CampusServiceClient.shared.fetchFee(kind)
                return ["resultFields": rows.keys.sorted(), "hasBalance": PhoneFeeAmount.balance(rows) != nil]
            }
            await check("laundryBalance") {
                let rows = try await CampusServiceClient.shared.fetchFee(.laundryHefei(phone: phone))
                return ["resultFields": rows.keys.sorted(), "hasBalance": PhoneFeeAmount.balance(rows) != nil]
            }
        } else { append(["service": "phoneBalances", "phase": "skipped", "reason": "profilePhoneUnavailable"]) }
        if CampusServiceClient.shared.hasSavedShowerCredentials {
            await check("showerProfile") {
                let value = try await CampusServiceClient.shared.fetchShowerProfile()
                return ["profileAvailable": value != nil]
            }
        }
        append(["phase": "finished"])
        lock.lock(); active = false; lock.unlock()
    }
    private static func check(_ service: String, operation: () async throws -> [String: Any]) async {
        do {
            let result = try await operation()
            append(result.merging(["service": service, "phase": "success"]) { _, new in new })
        } catch {
            append(["service": service, "phase": "failed", "message": PlatformDiagnosticRedactor.safeMessage(error.localizedDescription)])
        }
    }
    static func runServices() async {
        begin()
        let casURL = URL(string:"https://cas.hfut.edu.cn/cas/login")!
        let hasTGC = (HTTPCookieStorage.shared.cookies(for:casURL) ?? []).contains { ["TGC","CASTGC"].contains($0.name) }
        append(["mode":UserDefaults.standard.string(forKey:"academicConnectionMode") ?? "direct", "directTGCPresent":hasTGC])
        do {
            let token = try await CampusServiceClient.shared.refreshOnePortalToken()
            append(["service":"one","phase":"success","tokenPresent":!token.isEmpty])
        } catch { append(["service":"one","phase":"failed","message":error.localizedDescription]) }
        do {
            let rows = try await CampusServiceClient.shared.fetchSecondClassActivities(retrying:true)
            append(["service":"secondClass","phase":"success","count":rows.count])
        } catch { append(["service":"secondClass","phase":"failed","message":error.localizedDescription]) }
        do {
            let rows = try await CampusServiceClient.shared.fetchHefeiElectricOptions()
            append(["service":"electricityOptions","buildings":rows.map { ["name":$0.name,"value":$0.value] }])
        } catch { append(["service":"electricityOptions","phase":"failed","message":error.localizedDescription]) }
        lock.lock(); active = false; lock.unlock()
    }
}

/// Measures actual display callbacks while exercising the visible native UI.
/// Records timings and action names only; no account values or screen contents.
@MainActor final class NavigationFrameProbe: NSObject {
    private var displayLink: CADisplayLink?
    private var previous: CFTimeInterval?
    private var gaps: [Double] = []
    private var active = false
    private var reports: [[String: Any]] = []
    @objc private func tick(_ link: CADisplayLink) {
        defer { previous = link.timestamp }
        guard active, let previous else { return }
        gaps.append((link.timestamp - previous) * 1000)
    }
    private func step(_ name: String, action: () -> Void) async {
        gaps = []; previous = CACurrentMediaTime(); active = true
        action()
        try? await Task.sleep(for: .seconds(1.2))
        active = false
        reports.append(["action": name, "frames": gaps.count,
            "maxFrameGapMS": gaps.max() ?? 0,
            "meanFrameGapMS": gaps.isEmpty ? 0 : gaps.reduce(0,+) / Double(gaps.count),
            "gapsOver33MS": gaps.filter { $0 > 33.4 }.count])
    }
    static func run(state: AppState) async {
        let probe = NavigationFrameProbe()
        let link = CADisplayLink(target: probe, selector: #selector(tick(_:)))
        probe.displayLink = link
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        let original = state.selectedTab
        defer { link.invalidate(); state.selectedTab = original }
        try? await Task.sleep(for: .seconds(1))
        for pass in 0..<2 {
            for tab in [AppTab.schedule, .home, .services, .me] {
                await probe.step("tab-\(PlatformNavigationCoordinator.scope(for: tab))-\(pass)") { state.selectedTab = tab }
            }
        }
        state.selectedTab = .services
        try? await Task.sleep(for: .seconds(0.5))
        let coordinator = PlatformNavigationCoordinator.shared
        for featureID in [3, 1, 6] {
            guard let feature = FeatureCatalog.all.first(where: { $0.id == featureID }) else { continue }
            let route = coordinator.register(id: UUID(), title: feature.title) { FeatureDetailView(feature: feature) }
            await probe.step("open-feature-\(featureID)") { withAnimation(.default) { coordinator.setPath([route], scope: "services") } }
            await probe.step("close-feature-\(featureID)") { withAnimation(.default) { coordinator.setPath([], scope: "services") } }
        }
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("NavigationPerformance.json")
        let result: [String: Any] = ["system": ProcessInfo.processInfo.operatingSystemVersionString, "reports": probe.reports, "phase": "finished"]
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: url, options: .atomic) }
    }
}


/// Opt-in, simulator-only UI fixtures. Never compiled into public Release IPA.
@MainActor enum AppUIPreview {
    static var enabled: Bool {
        #if targetEnvironment(simulator)
        return ProcessInfo.processInfo.arguments.contains("--ui-preview")
        #else
        return false
        #endif
    }
    static let phone = "13800000000"
    static let weather = CampusWeatherReport(
        observation: .init(temperature: 15, apparent: 14, humidity: 55, condition: "晴", symbol: "sun.max.fill", windDescription: "东北风 2 级"),
        source: "示例数据", detailURL: CampusWeatherLocation.hefei.officialWeatherURL,
        warningURL: CampusWeatherLocation.hefei.officialWarningURL, warnings: .available([]),
        temperatureRange: .init(maximum: 19, minimum: 7, day: "2026-11-27", source: "示例数据"),
        tomorrowForecast: .init(temperatureRange: .init(maximum: 17, minimum: 8, day: "2026-11-28", source: "示例数据"), condition: "多云", symbol: "cloud.sun.fill"))
    static func phoneModel(_ service: PhoneFeeService) -> PhoneFeeBalanceModel {
        PhoneFeeBalanceModel(service: service) { _ in service == .bathing ? ["现金金额（单位：元）": "26.80"] : ["账户余额": "18.40"] }
    }
    static func electricityModel() -> ElectricityQueryModel {
        let defaults = ElectricityDefaultsStore(defaults: UserDefaults(suiteName: "HFUT.UI.Preview.Electricity")!)
        defaults.save(.init(building: "L", room: "L101", airConditioningBuilding: "A", airConditioningRoom: "A101"), for: .hefei)
        return ElectricityQueryModel(defaults: defaults, service: ElectricityFixture())
    }
    private struct ElectricityFixture: ElectricityServicing {
        func options(building: String?) async throws -> [HuiXinSelectionOption] {
            guard let building else { return [.init(name: "示例宿舍楼照明", value: "L"), .init(name: "示例宿舍楼空调", value: "A")] }
            return [.init(name: building == "L" ? "101照明" : "101空调", value: building + "101")]
        }
        func fee(for kind: HuiXinFeeKind) async throws -> [String: String] {
            let lighting = Dictionary(uniqueKeysWithValues: kind.fields)["building"] == "L"
            return ["剩余电量": lighting ? "58.00 kWh" : "36.80 kWh"]
        }
    }
    static func configure(state: AppState, courses: ScheduleStore, student: AcademicStudentStore) {
        state.campus = .hefei
        UserDefaults.standard.set("floating", forKey: "appBottomBarStyle")
        UserDefaults.standard.set(false, forKey: "courseRemindersEnabled")
        UserDefaults.standard.set(false, forKey: AppSettingsKey.dataReporting)
        student.replace(with: .init(studentID: "PREVIEW", name: "示例同学", fields: ["手机": phone]))
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let weekday = (Calendar.current.component(.weekday, from: tomorrow) + 5) % 7 + 1
        courses.replace(with: ["程序设计基础", "高等数学 A（上）", "线性代数"].enumerated().map { index, name in
            Course(name: name, teacher: "示例教师", location: "综合教学楼 301", weekday: weekday,
                startTime: ["08:00", "10:00", "14:00"][index], endTime: ["09:40", "11:40", "15:40"][index], colorIndex: index,
                dates: [HolidayCalendarStore.key(for: tomorrow)], source: "ui-preview", details: .init(code: "PREVIEW-\(index)"))
        })
        if ProcessInfo.processInfo.arguments.contains("--ui-preview-charge") {
            state.selectedTab = .home
            let route = PlatformNavigationCoordinator.shared.register(id: UUID(), title: "洗衣余额充值") {
                HuiXinFeeChargeView(itemID: 26, title: "洗衣余额充值")
            }
            PlatformNavigationCoordinator.shared.setPath([route], scope: "home")
        } else if ProcessInfo.processInfo.arguments.contains("--ui-preview-results") {
            state.selectedTab = .services
            let form = PlatformNavigationCoordinator.shared.register(id: UUID(), title: "挂科率") {
                OfficialFailRateView(courseName: "程序设计基础")
            }
            let route = PlatformNavigationCoordinator.shared.register(id: UUID(), title: "挂科率结果") {
                OfficialFailRateResultsView(courseName: "程序设计基础", lessonCode: nil)
            }
            PlatformNavigationCoordinator.shared.setPath([form, route], scope: "services")
        } else if ProcessInfo.processInfo.arguments.contains("--ui-preview-failrate") {
            state.open("hfut-schedule://open?feature=8")
        } else { state.selectedTab = .home }
    }
    static func failRates(course: String) -> [OfficialFailRateRecord] {
        [.init(courseName: course, courseCode: "示例课程", terms: [
            .init(year: "2025–2026", period: "1", averageScore: 81.5, totalCount: 200, failCount: 12, successRate: 0.94),
            .init(year: "2024–2025", period: "1", averageScore: 79.2, totalCount: 180, failCount: 15, successRate: 165.0 / 180)
        ])]
    }
}

#endif
