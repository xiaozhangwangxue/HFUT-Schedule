import Foundation

/// 校车班次（对应上游 v4.20.1 的校车 v2 数据，来源：https://www.hfut.edu.cn/xcxx.htm）。
struct CampusBusRoute: Identifiable, Equatable {
    let week: String
    let time: String
    let from: String
    let to: String
    let place: String
    let count: Int
    let stops: [String]

    var id: String { "\(week)|\(time)|\(from)|\(to)|\(place)" }

    /// 完整线路：起点 → 途经站 → 终点
    var points: [String] {
        ([from] + stops + [to]).filter { !$0.isEmpty }
    }
}

/// 解析校车时刻表网页（富文本表格），保持与 Android 版相同的字段。
struct CampusBusService {
    static let pageURL = URL(string: "https://www.hfut.edu.cn/xcxx.htm")!

    static func fetchRoutes() async throws -> [CampusBusRoute] {
        var request = URLRequest(url: pageURL)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let html: String
        if let utf8 = String(data: data, encoding: .utf8) {
            html = utf8
        } else if let gb = String(data: data, encoding: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))) {
            html = gb
        } else {
            throw URLError(.cannotDecodeContentData)
        }
        return parse(html)
    }

    static func parse(_ html: String) -> [CampusBusRoute] {
        guard let tableHTML = busTable(in: html) else { return [] }
        let rows = matches(tableHTML, #"(?is)<tr\b[^>]*>(.*?)</tr>"#)
        var currentWeek = ""
        var routes: [CampusBusRoute] = []

        for row in rows.dropFirst() {
            // 整格（含标签）匹配，便于过滤 display:none 的列
            let cellHTMLs = matches(row, #"(?is)(<t[dh]\b[^>]*>.*?</t[dh]>)"#)
            let visibleCells = cellHTMLs.filter { !$0.lowercased().contains("display: none") }
            guard !visibleCells.isEmpty else { continue }

            var cells = visibleCells
            if cells[0].lowercased().contains("rowspan") {
                currentWeek = clean(cells[0]).replacingOccurrences(of: " ", with: "")
                cells.removeFirst()
            }
            guard cells.count >= 6 else { continue }

            let fromTo = clean(cells[0]).components(separatedBy: "—")
            let place = clean(cells[2])
            let count = Int(clean(cells[4]).filter { $0.isNumber }) ?? 0
            let stops = clean(cells[3])
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
            routes.append(CampusBusRoute(
                week: currentWeek.replacingOccurrences(of: " ", with: ""),
                time: clean(cells[1]),
                from: fromTo.first ?? clean(cells[0]),
                to: fromTo.count > 1 ? fromTo[1] : clean(cells[0]),
                place: place,
                count: count,
                stops: stops
            ))
        }
        return routes
    }

    /// 取包含「运行区间」的表格（优先 docx_4 样式表）。
    private static func busTable(in html: String) -> String? {
        if let table = firstMatch(html, #"(?is)<table[^>]*class="[^"]*docx_4[^"]*"[^>]*>(.*?)</table>"#) {
            return table
        }
        for table in matches(html, #"(?is)<table\b[^>]*>(.*?)</table>"#) where clean(table).contains("运行区间") {
            return table
        }
        return nil
    }

    private static func matches(_ text: String, _ pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            guard let range = Range($0.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
    }

    private static func firstMatch(_ text: String, _ pattern: String) -> String? { matches(text, pattern).first }

    private static func clean(_ html: String) -> String {
        html
            .replacingOccurrences(of: #"(?is)<br\s*/?>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
