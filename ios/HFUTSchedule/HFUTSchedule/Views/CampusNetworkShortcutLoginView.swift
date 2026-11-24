import SwiftUI

struct CampusNetworkShortcutLoginView: View {
    let region: CampusNetworkRegion
    @EnvironmentObject private var student: AcademicStudentStore
    @State private var results: [CampusNetworkLoginResult] = []
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        List {
            Section {
                Text("与原版快捷磁贴一致，直接向校区校园网的 0.htm 提交登录请求。宣城会分别尝试两个认证网关。")
                    .font(.footnote).foregroundStyle(.secondary)
                Button(loading ? "正在登录…" : "重新登录校园网") { Task { await login() } }.disabled(loading)
                AppNavigationLink("网络凭据设置") { NetworkSettingsView() }
            }
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(results) { result in
                Section(result.server) { Label(result.message, systemImage: result.succeeded ? "checkmark.circle" : "exclamationmark.circle") }
            }
            Section("网页登录与状态") {
                ForEach(region.servers, id: \.absoluteString) { url in AppNavigationLink(url.host ?? "登录") { PortalWebView(url: url) } }
            }
        }.navigationTitle(region == .hefei ? "合肥校园网登录" : "宣城校园网登录").task { await login() }
    }
    @MainActor private func login() async {
        guard !loading else { return }
        loading = true; error = nil
        defer { loading = false }
        do {
            let (username, password) = try CampusNetworkLoginClient.savedCredentials(region: region, info: student.info)
            results = await CampusNetworkLoginClient().login(region: region, username: username, password: password)
        } catch { self.error = error.localizedDescription }
    }
}
