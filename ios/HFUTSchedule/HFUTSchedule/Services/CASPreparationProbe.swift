#if DEBUG
import Foundation

/// Opt-in, GET-only device diagnostic. Never records cookie values, credentials,
/// request bodies, response bodies, service tickets, or URL query strings.
enum CASPreparationProbe {
    private static let lock = NSLock()
    private static var active = false
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
    private static func begin() { lock.lock(); defer { lock.unlock() }; active = true; entries = []; save() }
    private static func append(_ entry: [String: Any]) {
        lock.lock(); defer { lock.unlock() }
        guard active else { return }
        entries.append(entry); save()
    }
    static func record(_ request: URLRequest, _ response: HTTPURLResponse, _ data: Data) {
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
#endif
