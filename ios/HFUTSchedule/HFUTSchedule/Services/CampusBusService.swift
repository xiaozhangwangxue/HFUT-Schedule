import Foundation

/// 校车班次（对应上游校车 v2 数据，来源：https://www.hfut.edu.cn/xcxx.htm）。
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

enum CampusBusDisplayMode: String, CaseIterable, Identifiable {
    case upcoming = "出行"
    case all = "所有安排"

    var id: String { rawValue }
}

struct CampusBusSelection: Equatable {
    let routes: [CampusBusRoute]
    let hasDepartedTrips: Bool

    var emptyMessage: String {
        hasDepartedTrips ? "今天的运营已结束" : "暂无班车安排"
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
            let visibleCells = cellHTMLs.filter {
                $0.range(of: #"(?i)display\s*:\s*none"#, options: .regularExpression) == nil
            }
            guard !visibleCells.isEmpty else { continue }

            var cells = visibleCells
            if cells[0].lowercased().contains("rowspan") {
                currentWeek = clean(cells[0]).replacingOccurrences(of: " ", with: "")
                cells.removeFirst()
            }
            guard cells.count >= 6 else { continue }

            let fromTo = clean(cells[0]).components(separatedBy: "—").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            // 上游把 7:5 规范为 07:05；无效时间不应进入实时班次计算。
            guard let departureMinute = minutes(afterMidnight: clean(cells[1])) else { continue }
            let place = clean(cells[2])
            let count = Int(clean(cells[4]).filter { $0.isNumber }) ?? 0
            let stops = clean(cells[3])
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
            routes.append(CampusBusRoute(
                week: currentWeek.replacingOccurrences(of: " ", with: ""),
                time: String(format: "%02d:%02d", departureMinute / 60, departureMinute % 60),
                from: fromTo.first ?? clean(cells[0]),
                to: fromTo.count > 1 ? fromTo[1] : clean(cells[0]),
                place: place,
                count: count,
                stops: stops
            ))
        }
        return routes
    }

    /// 与 BusNowScreen 相同：按自然星期匹配，节假日仅提示查看公告，不替换班次类别。
    static func weekdayGroup(for date: Date, calendar: Calendar = .current) -> String {
        switch calendar.component(.weekday, from: date) {
        case 1: return "周日"
        case 7: return "周六"
        default: return "周一至周五"
        }
    }

    static func select(
        _ routes: [CampusBusRoute],
        mode: CampusBusDisplayMode,
        date: Date,
        now: Date,
        from: String = "",
        to: String = "",
        calendar: Calendar = .current
    ) -> CampusBusSelection {
        let group = weekdayGroup(for: date, calendar: calendar)
        let matching = routes.filter {
            (mode == .all || $0.week == group) &&
            (from.isEmpty || $0.from.localizedCaseInsensitiveContains(from)) &&
            (to.isEmpty || $0.to.localizedCaseInsensitiveContains(to))
        }.sorted {
            let lhs = minutes(afterMidnight: $0.time) ?? Int.max
            let rhs = minutes(afterMidnight: $1.time) ?? Int.max
            return lhs == rhs ? $0.id < $1.id : lhs < rhs
        }
        guard mode == .upcoming, calendar.isDate(date, inSameDayAs: now) else {
            return CampusBusSelection(routes: matching, hasDepartedTrips: false)
        }
        let nowMinute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        // Android 将发车当分钟视为已开始，只有严格晚于当前分钟的班次保留。
        let upcoming = matching.filter { (minutes(afterMidnight: $0.time) ?? Int.max) > nowMinute }
        return CampusBusSelection(routes: upcoming, hasDepartedTrips: upcoming.count < matching.count)
    }

    static func minutes(afterMidnight time: String) -> Int? {
        let parts = time.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return hour * 60 + minute
    }

    /// 每次进入页面先立即计算，然后对齐下一整分钟刷新。
    static func secondsUntilNextMinute(from now: Date) -> TimeInterval {
        60 - now.timeIntervalSince1970.truncatingRemainder(dividingBy: 60)
    }

    static func holidayAdvisory(for day: HolidayDay?) -> String? {
        guard let day else { return nil }
        let kind = day.isOffDay ? "假期" : "调休工作日"
        return "此日期为\(kind)，点击查看调休通知公告，以实际安排为准。"
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
