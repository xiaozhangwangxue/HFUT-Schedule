import SwiftUI

struct PlatformShortcutsView: View {
    @State private var selected = HomeScreenShortcutStore.selected()
    var body: some View {
        List {
            Section {
                Text("长按桌面 App 图标可打开最多四个入口。拖动可排序；快捷指令 App 中的“打开校园快捷入口”支持全部入口。")
                    .font(.footnote).foregroundStyle(.secondary)
                ForEach(selected) { item in
                    HStack { Label(item.title, systemImage: item.symbol); Spacer(); Button(role: .destructive) { selected.removeAll { $0 == item }; save() } label: { Image(systemName: "minus.circle") } }
                }.onMove { from, to in selected.move(fromOffsets: from, toOffset: to); save() }
            } header: { Text("桌面快捷入口") }
            Section("添加入口") {
                ForEach(CampusShortcutTarget.allCases.filter { !selected.contains($0) }) { item in
                    Button { selected.append(item); save() } label: { Label(item.title, systemImage: item.symbol) }.disabled(selected.count >= 4)
                }
            }
            Section { AppNavigationLink("查看支持的深链") { PlatformDeepLinkCatalogView() } }
        }.navigationTitle("快捷入口").toolbar { EditButton() }
    }
    private func save() { HomeScreenShortcutStore.save(selected) }
}

struct PlatformShortcutLandingView: View {
    let target: CampusShortcutTarget
    @EnvironmentObject private var appState: AppState
    @Environment(\.openURL) private var openURL
    @State private var attempted = false
    @State private var openFailed = false
    var body: some View {
        Group {
            switch target {
            case .scanner: ScannerView()
            case .campusCard: CampusCardServiceView()
            case .payCode: FocusPayCodeView()
            case .library: LibraryServiceView()
            case .hefeiNetwork: CampusNetworkShortcutLoginView(region: .hefei)
            case .xuanchengNetwork: CampusNetworkShortcutLoginView(region: .xuancheng)
            case .schedule: ScheduleView()
            case .services: ServicesView()
            case .recharge, .hotWater, .expressPDD, .expressTaobao:
                List {
                    Section {
                        Button("打开\(target.title)", systemImage: "arrow.up.forward.app") { launchExternal() }
                        if openFailed { Text("未能打开对应 App，可使用下方网页入口或先安装对应 App。落地页面受第三方 App 支持情况影响。 ").font(.footnote).foregroundStyle(.secondary) }
                        if let fallback { AppNavigationLink("打开网页入口") { PortalWebView(url: fallback) } }
                    }
                }.navigationTitle(target.title).task { if !attempted { attempted = true; launchExternal() } }
            }
        }
    }
    private var fallback: URL? {
        switch target {
        case .recharge: CampusServiceClient.alipayCampusCardFallbackURL
        case .expressPDD: CampusServiceClient.pinduoduoExpressURL
        case .expressTaobao: CampusServiceClient.taobaoExpressURL
        default: nil
        }
    }
    private func launchExternal() {
        let url: URL
        switch target {
        case .recharge: url = CampusServiceClient.alipayCampusCardURL
        case .hotWater: url = URL(string: "alipays://platformapi/startapp?appId=20000067&url=https://ur.alipay.com/_3B2YzKjbV75xL9a2oapcNz")!
        case .expressPDD: url = CampusServiceClient.pinduoduoExpressURL
        case .expressTaobao: url = CampusServiceClient.taobaoExpressURL
        default: return
        }
        openURL(url) { accepted in openFailed = !accepted }
    }
}
