import SwiftUI
import Charts

enum LibraryKeywordAnalysis {
    static func frequencies(_ keywords: [String]) -> [(word: String, count: Int)] {
        var counts: [String: Int] = [:]
        for value in keywords {
            var parts = value.split(separator: "/").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if parts.count > 1, let first = parts.first,
               first.contains(" ") || first.first.map({ ("a"..."b").contains(String($0)) }) == true { parts.removeFirst() }
            for word in parts { counts[word, default: 0] += 1 }
        }
        return counts.map { (word: $0.key, count: $0.value) }.sorted { $0.count == $1.count ? $0.word < $1.word : $0.count > $1.count }
    }
}

struct LibraryKeywordAnalysisView: View {
    let records: [LibraryBorrowRecord]
    private var words: [(word: String, count: Int)] { LibraryKeywordAnalysis.frequencies(records.map { $0.libraryDetail.detail.keywords }) }
    var body: some View {
        List {
            Section("借阅关键词") {
                if words.isEmpty { Text("当前记录没有关键词信息").foregroundStyle(.secondary) }
                else {
                    Chart(Array(words.prefix(12)), id: \.word) { item in
                        BarMark(x: .value("次数", item.count), y: .value("关键词", item.word))
                            .foregroundStyle(AppTheme.accent)
                    }.frame(height: CGFloat(min(words.count, 12)) * 30 + 30)
                    ForEach(words, id: \.word) { item in LabeledContent(item.word, value: "\(item.count) 次") }
                }
            }
            Section { Text("根据当前已加载的\(records.count)条借阅记录计算；按原版规则清理关键词首项中的拼音。")
                .font(.caption).foregroundStyle(.secondary) }
        }.navigationTitle("借阅分析")
    }
}
