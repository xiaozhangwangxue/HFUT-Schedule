import SwiftUI

struct ThirdPartyShortcutsView: View {
    @Environment(\.openURL) private var openURL
    @State private var query = ""
    @State private var message: String?
    private var filtered: [ThirdPartyShortcut] {
        ThirdPartyShortcutCatalog.all.filter { query.isEmpty || ($0.title + " " + $0.detail).localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        List {
            Section {
                ForEach(filtered) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        Button { open(item) } label: {
                            HStack(spacing: 12) {
                                SettingsIcon(systemName: item.symbol)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title).foregroundStyle(.primary).font(.subheadline.weight(.medium))
                                    Text(item.detail).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(item.opening.rawValue).font(.caption2).foregroundStyle(.secondary)
                            }
                        }.buttonStyle(.plain)
                        if let text = item.copyText {
                            Button("复制小程序名称：\(text)", systemImage: "doc.on.doc") {
                                UIPasteboard.general.string = text
                                message = "已复制“\(text)”，可到微信中搜索。"
                            }.font(.caption)
                        }
                    }.padding(.vertical, 4)
                    .contextMenu {
                        Button("复制入口链接", systemImage: "link") { UIPasteboard.general.string = item.url.absoluteString }
                        ShareLink(item: item.url) { Label("分享入口", systemImage: "square.and.arrow.up") }
                        if let fallback = item.fallback { Button("打开备用官网") { openURL(fallback) } }
                    }
                }
            } footer: {
                Text("iOS 使用官方网页、App Store 或支付宝公开跳转方式。App Store 中已安装的应用可点“打开”；网页能否直接唤起应用由服务方决定。")
            }
        }.navigationTitle("第三方应用")
            .searchable(text: $query, prompt: "搜索应用或服务")
            .alert("第三方应用", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("好") { message = nil }
            } message: { Text(message ?? "") }
    }
    private func open(_ item: ThirdPartyShortcut) {
        openURL(item.url) { accepted in
            guard !accepted else { return }
            if let fallback = item.fallback {
                openURL(fallback) { fallbackAccepted in if !fallbackAccepted { message = "未能打开入口，可长按复制链接后重试。" } }
            } else { message = "未能打开入口，可长按复制链接后重试。" }
        }
    }
}
