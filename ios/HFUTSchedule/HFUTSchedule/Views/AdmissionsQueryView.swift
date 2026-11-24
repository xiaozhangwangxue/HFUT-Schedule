import SwiftUI

enum AdmissionQueryKind: String, CaseIterable, Identifiable {
    case plan = "zsjh", history = "lnfs"
    var id: String { rawValue }
    var title: String { self == .plan ? "招生计划" : "历年分数" }
}
struct AdmissionChoice: Decodable, Identifiable, Equatable {
    let subject: String
    let campus: String
    let year: String
    let type: String
    var id: String { "\(year)|\(campus)|\(type)|\(subject)" }
    var title: String { "\(year)年 · \(campus) · \(type) · \(subject)" }
    enum CodingKeys: String, CodingKey { case subject = "klmc", campus, year = "nf", type = "zslx" }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        func string(_ key: CodingKeys) -> String {
            (try? values.decode(String.self, forKey:key)) ?? (try? values.decode(Int.self,forKey:key)).map(String.init) ?? ""
        }
        subject = string(.subject); campus = string(.campus); year = string(.year); type = string(.type)
    }
}
struct AdmissionResultRow: Identifiable {
    let id: String
    let title: String
    let fields: [(String, String)]
}
struct AdmissionQueryClient {
    private let client = CampusDirectoryClient()
    private static let base = URL(string: "https://bkzs.hfut.edu.cn/")!
    func choices(_ kind: AdmissionQueryKind) async throws -> [String: [AdmissionChoice]] {
        let root = try ScheduleSourceParser.object(await client.data(request("f/ajax_\(kind.rawValue)_param")))
        guard let map = (root["data"] as? [String: Any])?["ssmc_nf_zslx_sex_campus_klmc_Map"], JSONSerialization.isValidJSONObject(map) else {
            throw OfficialCampusAPIError.invalidData("招生查询条件格式无效")
        }
        return try JSONDecoder().decode([String: [AdmissionChoice]].self, from: JSONSerialization.data(withJSONObject: map))
    }
    func details(_ kind: AdmissionQueryKind, region: String, choice: AdmissionChoice) async throws -> [AdmissionResultRow] {
        var tokenRequest = request("f/ajax_get_csrfToken"); tokenRequest.httpBody = Data("n=1".utf8)
        let token = try ScheduleSourceParser.object(await client.data(tokenRequest))
        guard let cookie = token["jessionid"] as? String, let csrf = token["data"] as? String, !cookie.isEmpty, !csrf.isEmpty else {
            throw OfficialCampusAPIError.invalidData("招生查询未取得有效会话，请重试")
        }
        var detail = request("f/ajax_\(kind.rawValue)")
        detail.setValue("zhaosheng.hfut.session.id=" + cookie, forHTTPHeaderField: "Cookie")
        detail.setValue(csrf, forHTTPHeaderField: "Csrf-Token")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        detail.httpBody = ["ssmc":region,"zsnf":choice.year,"klmc":choice.subject,"campus":choice.campus,"zslx":choice.type]
            .sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&").data(using: .utf8)
        let root = try ScheduleSourceParser.object(await client.data(detail))
        guard let data = root["data"] as? [String: Any] else { throw OfficialCampusAPIError.invalidData("没有查询到招生结果") }
        let keys = kind == .plan ? ["zsjhTotal","zsjhList"] : ["zsSsgradeList","sszygradeList"]
        let fields = kind == .plan
            ? [("zsjhs","招生数"),("xkkm","选科要求"),("sxkmyqzw","首选科目"),("zyxf","学费"),("remarks","说明")]
            : [("minScore","最低分"),("maxScore","最高分"),("avgScore","平均分"),("fsx","控制线")]
        return keys.enumerated().flatMap { group, key in
            (data[key] as? [[String: Any]] ?? []).enumerated().map { index, row in
                AdmissionResultRow(id: "\(key)|\(index)", title: row[kind == .plan ? "zydhmc" : "zymc"] as? String ?? "概况",
                    fields: fields.compactMap { key, title in
                        guard let value = row[key], !(value is NSNull), !String(describing: value).isEmpty else { return nil }
                        return (title, String(describing: value))
                    })
            }
        }
    }
    private func request(_ path: String) -> URLRequest {
        var request = URLRequest(url: URL(string: path, relativeTo: Self.base)!.absoluteURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue(path.hasSuffix("_param") ? "1" : "", forHTTPHeaderField: "X-Requested-Time")
        request.setValue(Self.base.absoluteString, forHTTPHeaderField: "Referer")
        return request
    }
}

struct AdmissionsQueryView: View {
    @State private var kind = AdmissionQueryKind.plan
    @State private var map: [String: [AdmissionChoice]] = [:]
    @State private var region = ""
    @State private var selectedID = ""
    @State private var rows: [AdmissionResultRow] = []
    @State private var busy = false
    @State private var error: String?
    @State private var generation = UUID()
    private let client = AdmissionQueryClient()
    private var choices: [AdmissionChoice] { (map[region] ?? []).sorted { $0.year > $1.year } }
    var body: some View {
        List {
            Section("查询条件") {
                Picker("类别", selection: $kind) { ForEach(AdmissionQueryKind.allCases) { Text($0.title).tag($0) } }
                Picker("地区", selection: $region) { ForEach(map.keys.sorted(), id: \.self) { Text($0).tag($0) } }
                Picker("年份与科类", selection: $selectedID) { ForEach(choices) { Text($0.title).tag($0.id) } }
                Button("查询") { Task { await query() } }.disabled(busy || choices.isEmpty)
            }
            ForEach(rows) { row in
                Section(row.title) {
                    ForEach(Array(row.fields.enumerated()), id: \.offset) { _, field in LabeledContent(field.0, value: field.1) }
                }
            }
            if busy { ProgressView() }
            if let error { Text(error).foregroundStyle(.red) }
        }.navigationTitle("招生信息")
            .task(id: kind) { await loadChoices() }
            .onChange(of: region) { _, _ in selectedID = choices.first?.id ?? ""; invalidate() }
            .onChange(of: selectedID) { _, _ in invalidate() }
    }
    private func invalidate() { generation = UUID(); busy = false; rows = [] }
    private func loadChoices() async {
        let token = UUID(); generation = token; busy = true; error = nil; rows = []
        defer { if generation == token { busy = false } }
        do {
            let result = try await client.choices(kind)
            guard generation == token, !Task.isCancelled else { return }
            map = result; region = result.keys.sorted().first ?? ""; selectedID = choices.first?.id ?? ""
            if result.values.allSatisfy(\.isEmpty) { error = "学校当前没有发布可查询的\(kind.title)条件，可切换另一类别或稍后重试。" }
        } catch { if generation == token { self.error = error.localizedDescription } }
    }
    private func query() async {
        guard let choice = choices.first(where: { $0.id == selectedID }) else { return }
        let token = UUID(); generation = token; busy = true; error = nil
        defer { if generation == token { busy = false } }
        do {
            let result = try await client.details(kind, region: region, choice: choice)
            guard generation == token, selectedID == choice.id else { return }
            rows = result
            if result.isEmpty { error = "所选条件暂无数据" }
        } catch { if generation == token { self.error = error.localizedDescription } }
    }
}
