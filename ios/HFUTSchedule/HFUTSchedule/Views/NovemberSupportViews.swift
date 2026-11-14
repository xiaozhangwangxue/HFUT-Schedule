import SwiftUI
import UIKit

struct FocusPayCodeView: View {
    @State private var url: URL?
    @State private var error: String?
    var body: some View {
        Group {
            if let url { PortalWebView(url: url) }
            else if let error { ContentUnavailableView("付款码暂不可用", systemImage: "qrcode", description: Text(error)) }
            else { ProgressView("正在获取付款码…") }
        }
        .navigationTitle("付款码")
        .task {
            do { url = try await CampusServiceClient.shared.huiXinPayCodeURL() }
            catch { self.error = error.localizedDescription }
        }
    }
}

enum BirthdayGreeting {
    static func isBirthday(fields: [String: String], on date: Date, calendar: Calendar = .current) -> Bool {
        guard let value = fields["出生日期"] ?? fields["出生年月日"] ?? fields["生日"] else { return false }
        let parts = value.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init)
        guard parts.count >= 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return false }
        return calendar.component(.month, from: date) == parts[1] && calendar.component(.day, from: date) == parts[2]
    }
}

struct DeveloperInfoView: View {
    var body: some View {
        List {
            Section("运行环境") {
                LabeledContent("应用版本", value: AppInfo.version)
                LabeledContent("系统", value: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
                LabeledContent("设备类型", value: UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")
                LabeledContent("运行方式", value: "原生 SwiftUI")
                LabeledContent("上游已发布版本", value: "4.21.4.1")
                LabeledContent("上游同步提交", value: "b3cb252e · 2026-11-13")
                LabeledContent("请求范围", value: "\(UserDefaults.standard.integer(forKey: AppSettingsKey.pageSize))")
            }
            Section {
                Text("登录 Cookie、账号密码和 API Key 不在此页面显示，也不包含在备份中。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("开发者选项")
    }
}
