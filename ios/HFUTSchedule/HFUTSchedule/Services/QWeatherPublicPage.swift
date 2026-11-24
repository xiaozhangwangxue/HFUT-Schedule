import Foundation

/// Public city pages provide current conditions and local warnings without
/// distributing the Android project's account signing key in another binary.
enum QWeatherPublicPage {
    static func observation(_ html: String) throws -> CampusWeatherObservation {
        guard let live = element("current-live", in: html), let basic = element("current-basic", in: html) else {
            throw CampusWeatherError.invalidObservation
        }
        let current = paragraphs(live), fields = paragraphs(basic)
        guard current.count >= 2, let temperature = number(current[0]),
              let humidityIndex = fields.firstIndex(of: "相对湿度"), humidityIndex > 0,
              let humidity = number(fields[humidityIndex - 1]), (0...100).contains(humidity),
              let apparentIndex = fields.firstIndex(of: "体感温度"), apparentIndex > 0,
              let apparent = number(fields[apparentIndex - 1]) else { throw CampusWeatherError.invalidObservation }
        let condition = current[1]
        let symbol: String
        if condition.contains("雪") { symbol = "cloud.snow.fill" }
        else if condition.contains("雷") { symbol = "cloud.bolt.rain.fill" }
        else if condition.contains("雨") { symbol = "cloud.rain.fill" }
        else if condition.contains("霾") || condition.contains("雾") { symbol = "cloud.fog.fill" }
        else if condition.contains("晴") { symbol = "sun.max.fill" }
        else { symbol = "cloud.fill" }
        return CampusWeatherObservation(temperature: temperature, apparent: apparent, humidity: Int(humidity),
            condition: condition, symbol: symbol, windDescription: fields.prefix(2).joined(separator: " "))
    }

    static func warnings(_ html: String) throws -> [CampusWeatherWarning] {
        if let empty = element("c-city-warning-no-data", in: html), text(empty).contains("暂无预警") { return [] }
        var remaining = html, result: [CampusWeatherWarning] = []
        while let block = extract("c-city-warning-events", in: remaining) {
            let value = block.content
            guard let title = captures(#"<h3\b[^>]*>([\s\S]*?)</h3>"#, in: value).first.map(text),
                  let detail = element("warning-events__txt", in: value).map(text), !title.isEmpty, !detail.isEmpty else {
                throw CampusWeatherError.invalidObservation
            }
            result.append(CampusWeatherWarning(title: title, typeName: "气象预警", text: detail))
            remaining = String(remaining[block.end...])
        }
        guard !result.isEmpty else { throw CampusWeatherError.invalidObservation }
        return result
    }

    static func text(_ html: String) -> String {
        html.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&deg;", with: "°").replacingOccurrences(of: "&#176;", with: "°")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private static func number(_ text: String) -> Double? {
        captures(#"(-?\d+(?:\.\d+)?)"#, in: text.replacingOccurrences(of: "−", with: "-")).first.flatMap(Double.init)
    }
    private static func paragraphs(_ html: String) -> [String] { captures(#"<p\b[^>]*>([\s\S]*?)</p>"#, in: html).map(text) }
    private static func captures(_ pattern: String, in source: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        return regex.matches(in: source, range: NSRange(source.startIndex..., in: source)).compactMap {
            Range($0.range(at: 1), in: source).map { String(source[$0]) }
        }
    }
    private static func element(_ name: String, in source: String) -> String? { extract(name, in: source)?.content }
    private static func extract(_ name: String, in source: String) -> (content: String, end: String.Index)? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let pattern = #"<([a-z][a-z0-9]*)\b[^>]*\bclass=["'][^"']*\b"# + escaped + #"\b[^"']*["'][^>]*>"#
        guard let opening = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = opening.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
              let tagRange = Range(match.range(at: 1), in: source), let openRange = Range(match.range, in: source) else { return nil }
        let tag = String(source[tagRange])
        guard let boundaries = try? NSRegularExpression(pattern: "</?" + tag + #"\b[^>]*>"#, options: .caseInsensitive) else { return nil }
        var depth = 1
        for node in boundaries.matches(in: source, range: NSRange(openRange.upperBound..., in: source)) {
            guard let range = Range(node.range, in: source) else { continue }
            if source[range].hasPrefix("</") { depth -= 1 } else if !source[range].hasSuffix("/>") { depth += 1 }
            if depth == 0 { return (String(source[openRange.upperBound..<range.lowerBound]), range.upperBound) }
        }
        return nil
    }
}
