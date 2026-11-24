import SwiftUI

struct PlatformDiagnosticsView: View {
    @ObservedObject private var store = PlatformDiagnosticsStore.shared
    var body: some View {
        List {
            Section { Text("错误记录只保留在本次运行的内存中，不自动上传。复制前会隐藏常见凭据字段。") .font(.footnote).foregroundStyle(.secondary) }
            if store.reports.isEmpty { ContentUnavailableView("本次运行没有错误记录", systemImage: "checkmark.seal") }
            ForEach(store.reports) { report in
                AppNavigationLink { PlatformDiagnosticDetailView(report: report) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(report.context).font(.headline)
                        Text(report.message).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                        Text(report.createdAt.formatted()).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }.navigationTitle("错误详情")
            .toolbar { Button("清除", role: .destructive) { store.clear() }.disabled(store.reports.isEmpty) }
    }
}

struct PlatformDiagnosticDetailView: View {
    let report: PlatformDiagnosticReport
    var body: some View {
        ScrollView { Text(report.exportText).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding() }
            .navigationTitle(report.context).navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("复制详情", systemImage: "doc.on.doc") { UIPasteboard.general.string = report.exportText } }
    }
}
