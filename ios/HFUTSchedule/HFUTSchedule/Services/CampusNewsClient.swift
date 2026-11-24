import Foundation

struct CampusNewsItem: Identifiable, Equatable {
    let title: String
    let date: String
    let url: URL
    var id: String { url.absoluteString }
}
struct CampusDepartment: Identifiable, Equatable {
    let name: String
    let url: URL
    let iconURL: URL?
    var id: String { name + url.absoluteString }
}
struct CampusNewsPage {
    let items: [CampusNewsItem]
    let totalPages: Int
}
struct CampusNewsCategory: Identifiable, Hashable {
    enum Source: String, Codable { case hefeiAcademic, xuanchengAcademic, xuanchengCampus }
    let source: Source
    let code: String
    let title: String
    var id: String { source.rawValue + ":" + code }
    var baseURL: URL {
        switch source {
        case .hefeiAcademic: URL(string: "https://jwc.hfut.edu.cn/")!
        case .xuanchengAcademic: URL(string: "https://xcjwb.hfut.edu.cn/")!
        case .xuanchengCampus: URL(string: "https://xc.hfut.edu.cn/")!
        }
    }
    static let xuanchengNotices = Self(source: .xuanchengCampus, code: "1955", title: "宣城校区通知公告")
    static let hefeiAcademic: [Self] = [
        .init(source: .hefeiAcademic, code: "tzgg/jxbzl", title: "教学布置"),
        .init(source: .hefeiAcademic, code: "tzgg/cxcyl", title: "创新创业"),
        .init(source: .hefeiAcademic, code: "tzgg/qt", title: "其他"),
        .init(source: .hefeiAcademic, code: "wdxz", title: "文档下载"),
        .init(source: .hefeiAcademic, code: "gzzd/gjgzzd", title: "国家规章制度"),
        .init(source: .hefeiAcademic, code: "gzzd/xxgzzd", title: "学习规章制度"),
        .init(source: .hefeiAcademic, code: "gzzd/sjgzzd", title: "省级规章制度")
    ]
    static let xuanchengAcademic: [Self] = [
        .init(source: .xuanchengAcademic, code: "1177", title: "教学安排"), .init(source: .xuanchengAcademic, code: "1178", title: "考试信息"),
        .init(source: .xuanchengAcademic, code: "1179", title: "学籍管理"), .init(source: .xuanchengAcademic, code: "1183", title: "创新创业"),
        .init(source: .xuanchengAcademic, code: "1184", title: "学科竞赛"), .init(source: .xuanchengAcademic, code: "573", title: "新闻公告"),
        .init(source: .xuanchengAcademic, code: "713", title: "新闻动态"), .init(source: .xuanchengAcademic, code: "714", title: "通知公告"),
        .init(source: .xuanchengAcademic, code: "1180", title: "校历"), .init(source: .xuanchengAcademic, code: "2186", title: "办公人员"),
        .init(source: .xuanchengAcademic, code: "2187", title: "教学秘书"), .init(source: .xuanchengAcademic, code: "1143", title: "上级文件"),
        .init(source: .xuanchengAcademic, code: "1144", title: "校内文件"), .init(source: .xuanchengAcademic, code: "1145", title: "教务管理"),
        .init(source: .xuanchengAcademic, code: "1146", title: "实践教学"), .init(source: .xuanchengAcademic, code: "1147", title: "创新教学"),
        .init(source: .xuanchengAcademic, code: "1148", title: "质量管理"), .init(source: .xuanchengAcademic, code: "1149", title: "实验教学"),
        .init(source: .xuanchengAcademic, code: "1150", title: "办事流程")
    ]
}

struct CampusNewsClient {
    let session: URLSession
    init(session: URLSession = .shared) { self.session = session }
    static let departmentsURL = URL(string: "https://www.hfut.edu.cn/jgsz/yxsz.htm")!
    static func pageURL(category: CampusNewsCategory, page: Int, totalPages: Int? = nil) -> URL {
        let page = max(1, page)
        switch category.source {
        case .hefeiAcademic:
            if page == 1 || totalPages == nil { return category.baseURL.appendingPathComponent(category.code + ".htm") }
            return category.baseURL.appendingPathComponent(category.code + "/\(max(1, totalPages! - page + 1)).htm")
        case .xuanchengAcademic: return category.baseURL.appendingPathComponent("\(category.code)/list\(page).htm")
        case .xuanchengCampus: return category.baseURL.appendingPathComponent("\(category.code)/list\(page == 1 ? "" : String(page)).htm")
        }
    }
    func fetch(category: CampusNewsCategory, page: Int, totalPages: Int?) async throws -> CampusNewsPage {
        let url = Self.pageURL(category: category, page: page, totalPages: totalPages)
        let html = try await html(at: url)
        return Self.parse(html, category: category, pageURL: url)
    }
    func departments() async throws -> [CampusDepartment] { Self.parseDepartments(try await html(at: Self.departmentsURL)) }
    private func html(at url: URL) async throws -> String {
        var request = URLRequest(url: url); request.timeoutInterval = 25
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode), data.count < 8_388_608,
              let html = String(data: data, encoding: .utf8), html.lowercased().contains("<html") else { throw CampusNewsError.invalidPage }
        return html
    }
    static func safeURL(_ text: String, relativeTo base: URL) -> URL? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.hasPrefix("#"), let url = URL(string: text, relativeTo: base)?.absoluteURL,
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }
    static func parse(_ html: String, category: CampusNewsCategory, pageURL: URL) -> CampusNewsPage {
        let document = AcademicHTMLElement.parse(html), elements = document.descendants.filter { !hasScriptAncestor($0) }
        var items: [CampusNewsItem] = [], seen = Set<String>()
        func append(title: String, date: String, link: String) {
            guard !title.isEmpty, let url = safeURL(link, relativeTo: pageURL), seen.insert(url.absoluteString).inserted else { return }
            items.append(CampusNewsItem(title: title, date: date, url: url))
        }
        switch category.source {
        case .hefeiAcademic:
            for anchor in elements where anchor.tag == "a" && anchor.classes.contains("l3-news--item") {
                let nodes = anchor.descendants
                let title = nodes.first { $0.classes.contains("l3-news--title") }?.normalizedText ?? ""
                let month = nodes.first { $0.classes.contains("l3-news--month") }?.normalizedText ?? ""
                let day = nodes.first { $0.classes.contains("l3-news--day") }?.normalizedText ?? ""
                append(title: title, date: month + (day.isEmpty ? "" : "-" + day), link: anchor.attributes["href"] ?? "")
            }
        case .xuanchengAcademic:
            for anchor in elements where anchor.tag == "a" && anchor.attributes["target"] == "_blank" && anchor.parent?.tag == "td" && anchor.parent?.attributes["align"]?.lowercased() == "left" {
                guard let row = anchor.parent?.parent, row.tag == "tr",
                      let date = row.children.first(where: { $0.tag == "td" && $0.attributes["align"]?.lowercased() == "right" })?.normalizedText else { continue }
                let title = anchor.attributes["title"] ?? anchor.normalizedText
                append(title: title, date: date, link: anchor.attributes["href"] ?? "")
            }
        case .xuanchengCampus:
            for list in elements where list.tag == "ul" && list.classes.contains("news_list") {
                for row in list.children where row.tag == "li" {
                    let nodes = row.descendants
                    guard let anchor = nodes.first(where: { $0.tag == "a" && $0.parent?.classes.contains("news_title") == true }) else { continue }
                    append(title: anchor.attributes["title"] ?? anchor.normalizedText,
                        date: nodes.first { $0.classes.contains("news_meta") }?.normalizedText ?? "", link: anchor.attributes["href"] ?? "")
                }
            }
        }
        let numbered = elements.filter { $0.tag == "a" && $0.parent?.classes.contains("p_no") == true }.compactMap { Int($0.normalizedText) }
        let webplus = elements.filter { $0.classes.contains("all_pages") }.compactMap { Int($0.normalizedText) }
        return CampusNewsPage(items: items, totalPages: max(1, min(10_000, (numbered + webplus).max() ?? 1)))
    }
    private static func hasScriptAncestor(_ node: AcademicHTMLElement) -> Bool {
        var ancestor = node.parent
        while let current = ancestor {
            if ["script", "style"].contains(current.tag) { return true }
            ancestor = current.parent
        }
        return false
    }
    static func parseDepartments(_ html: String) -> [CampusDepartment] {
        let root = AcademicHTMLElement.parse(html)
        var result: [CampusDepartment] = [], seen = Set<String>()
        for list in root.descendants where list.tag == "ul" && list.classes.contains("sz-list") && !hasScriptAncestor(list) {
            for row in list.children where row.tag == "li" {
                let nodes = row.descendants
                guard let anchor = nodes.first(where: { $0.tag == "a" }),
                      let name = nodes.first(where: { $0.classes.contains("sz-list-tt") })?.normalizedText, !name.isEmpty,
                      let url = safeURL(anchor.attributes["href"] ?? "", relativeTo: departmentsURL),
                      let host = url.host?.lowercased(), (host == "hfut.edu.cn" || host.hasSuffix(".hfut.edu.cn")), seen.insert(url.absoluteString).inserted else { continue }
                let icon = nodes.first { $0.tag == "img" && $0.parent?.tag == "font" }.flatMap { safeURL($0.attributes["src"] ?? "", relativeTo: departmentsURL) }
                result.append(CampusDepartment(name: name, url: url, iconURL: icon))
            }
        }
        return result
    }
}
enum CampusNewsError: LocalizedError {
    case invalidPage
    var errorDescription: String? { "学校网站未返回可读取的新闻页面，请重试或打开原网页" }
}
