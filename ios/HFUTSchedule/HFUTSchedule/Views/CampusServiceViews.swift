import SwiftUI

struct CampusCardServiceView: View {
    @State private var cards: [HuiXinCard] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingLogin = false

    var body: some View {
        List {
            if !cards.isEmpty {
                ForEach(cards) { card in
                    Section(card.name) {
                        LabeledContent("余额", value: card.balance.formatted(.currency(code: "CNY")))
                        LabeledContent("未结算金额", value: card.unsettledAmount.formatted(.currency(code: "CNY")))
                        LabeledContent("卡号", value: card.account)
                        LabeledContent("自动转账限额", value: card.autoTransferLimit.formatted(.currency(code: "CNY")))
                    }
                }
            }
            if let errorMessage {
                Section {
                    ContentUnavailableView("一卡通读取失败", systemImage: "creditcard.trianglebadge.exclamationmark", description: Text(errorMessage))
                    Button("前往安全登录", systemImage: "lock.shield") { showingLogin = true }
                }
            }
            Section("原版官方入口") {
                if let url = CampusServiceClient.shared.savedHuiXinPortalURL() {
                    NavigationLink("余额、账单、充值与卡管理") { PortalWebView(url: url) }
                } else {
                    Button("登录后打开完整一卡通", systemImage: "key") { showingLogin = true }
                }
                if let url = CampusServiceClient.shared.savedHuiXinPortalURL(path: "plat/pay") {
                    NavigationLink("付款码") { PortalWebView(url: url) }
                }
            }
        }
        .navigationTitle("一卡通")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if isLoading { ProgressView("正在读取一卡通…") } }
        .task { await load() }
        .refreshable { await load(forceRefresh: true) }
        .sheet(isPresented: $showingLogin, onDismiss: { Task { await load() } }) {
            NavigationStack { LoginPortalView() }
        }
    }

    @MainActor
    private func load(forceRefresh: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do { cards = try await CampusServiceClient.shared.fetchCampusCards(forceRefresh: forceRefresh) }
        catch { errorMessage = error.localizedDescription }
        isLoading = false
    }
}

struct ElectricityServiceView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("electricityBuilding") private var building = ""
    @AppStorage("electricityRoom") private var room = ""
    @State private var results: [String: String] = [:]
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingLogin = false

    private var itemID: Int { appState.campus == .hefei ? 1 : 261 }

    var body: some View {
        List {
            Section("\(appState.campus.rawValue)寝室电费") {
                if appState.campus == .hefei {
                    TextField("楼栋编号", text: $building)
                }
                TextField("寝室编号", text: $room)
                Button("查询电费", systemImage: "bolt.meter") { Task { await query() } }
                    .disabled(isLoading || room.trimmed.isEmpty || (appState.campus == .hefei && building.trimmed.isEmpty))
            }
            if !results.isEmpty {
                Section("查询结果") {
                    ForEach(results.keys.sorted(), id: \.self) { key in
                        LabeledContent(key, value: results[key] ?? "")
                    }
                }
            }
            if let errorMessage {
                Section {
                    ContentUnavailableView("电费查询失败", systemImage: "bolt.slash", description: Text(errorMessage))
                    Button("前往安全登录", systemImage: "lock.shield") { showingLogin = true }
                }
            }
            Section("官方缴费") {
                if let url = CampusServiceClient.shared.savedHuiXinChargeURL(itemID: itemID) {
                    NavigationLink("打开慧新易校电费入口") { PortalWebView(url: url) }
                } else {
                    Button("登录后打开缴费入口") { showingLogin = true }
                }
            }
        }
        .navigationTitle("宿舍电费")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if isLoading { ProgressView("正在查询电费…") } }
        .sheet(isPresented: $showingLogin) { NavigationStack { LoginPortalView() } }
    }

    @MainActor
    private func query() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            let kind: HuiXinFeeKind = appState.campus == .hefei
                ? .electricHefei(building: building.trimmed, room: room.trimmed)
                : .electricXuancheng(room: room.trimmed)
            results = try await CampusServiceClient.shared.fetchFee(kind)
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }
}

struct CampusNetworkServiceView: View {
    @EnvironmentObject private var appState: AppState
    @State private var results: [String: String] = [:]
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingLogin = false

    private var loginURLs: [(String, URL)] {
        if appState.campus == .hefei {
            return [("合肥校区校园网登录/状态", URL(string: "http://172.16.200.11/")!)]
        }
        return [
            ("宣城校区校园网（宿舍/图书馆）", URL(string: "http://172.18.3.3/")!),
            ("宣城校区校园网（敬亭/新安）", URL(string: "http://172.18.2.2/")!)
        ]
    }

    var body: some View {
        List {
            Section {
                ForEach(loginURLs, id: \.0) { item in
                    NavigationLink(item.0) { PortalWebView(url: item.1) }
                }
                NavigationLink("校园网自助服务与历史用量") {
                    PortalWebView(url: URL(string: "https://xywzz.hfut.edu.cn:8443/Self/LoginAction.action")!)
                }
            } header: {
                Text("当前网络登录与状态")
            } footer: {
                Text("这些入口与 Android 原版一致，只能在对应校园网环境访问；网页登录态会安全保存并在下次打开时自动恢复。")
            }
            if appState.campus == .xuancheng {
                Section("慧新易校校园网余额") {
                    Button("查询余额与流量", systemImage: "network") { Task { await queryHuiXin() } }
                    if !results.isEmpty {
                        ForEach(results.keys.sorted(), id: \.self) { key in
                            LabeledContent(key, value: results[key] ?? "")
                        }
                    }
                }
            }
            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                    Button("前往安全登录") { showingLogin = true }
                }
            }
        }
        .navigationTitle("校园网")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if isLoading { ProgressView("正在查询校园网…") } }
        .sheet(isPresented: $showingLogin) { NavigationStack { LoginPortalView() } }
    }

    @MainActor
    private func queryHuiXin() async {
        isLoading = true
        errorMessage = nil
        do { results = try await CampusServiceClient.shared.fetchFee(.networkXuancheng) }
        catch { errorMessage = error.localizedDescription }
        isLoading = false
    }
}

struct BathingServiceView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("bathingPhone") private var phone = ""
    @State private var password = ""
    @State private var profile: ShowerProfile?
    @State private var feeResults: [String: String] = [:]
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingLogin = false

    private var itemID: Int { appState.campus == .hefei ? 222 : 223 }

    var body: some View {
        List {
            if let profile {
                Section("呱呱物联") {
                    LabeledContent("姓名", value: profile.name)
                    LabeledContent("手机号", value: profile.phone.maskedPhone)
                    LabeledContent("余额", value: profile.balance.formatted(.currency(code: "CNY")))
                    LabeledContent("赠送余额", value: profile.giftedBalance.formatted(.currency(code: "CNY")))
                    Button("刷新洗浴账户", systemImage: "arrow.clockwise") { Task { await loadProfile() } }
                }
            } else {
                Section {
                    TextField("手机号", text: $phone).keyboardType(.phonePad)
                    SecureField("洗浴平台密码", text: $password)
                    Button("登录并保存令牌", systemImage: "key") { Task { await loginShower() } }
                        .disabled(phone.trimmed.isEmpty || password.isEmpty || isLoading)
                } header: {
                    Text("呱呱物联登录")
                } footer: {
                    Text("密码仅用于本次登录；应用只把平台返回的 loginCode 保存到系统钥匙串。")
                }
            }
            Section("慧新易校洗浴") {
                TextField("绑定手机号", text: $phone).keyboardType(.phonePad)
                Button("查询洗浴余额", systemImage: "shower") { Task { await queryFee() } }
                    .disabled(phone.trimmed.isEmpty || isLoading)
                ForEach(feeResults.keys.sorted(), id: \.self) { key in
                    LabeledContent(key, value: feeResults[key] ?? "")
                }
                if let url = CampusServiceClient.shared.savedHuiXinChargeURL(itemID: itemID) {
                    NavigationLink("打开官方充值入口") { PortalWebView(url: url) }
                }
            }
            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                    Button("前往安全登录") { showingLogin = true }
                }
            }
        }
        .navigationTitle("洗浴")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if isLoading { ProgressView("正在连接洗浴平台…") } }
        .task { await loadProfile(silently: true) }
        .sheet(isPresented: $showingLogin) { NavigationStack { LoginPortalView() } }
    }

    @MainActor
    private func loginShower() async {
        isLoading = true
        errorMessage = nil
        do {
            profile = try await CampusServiceClient.shared.loginShower(phone: phone.trimmed, password: password)
            password = ""
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    @MainActor
    private func loadProfile(silently: Bool = false) async {
        if !silently { isLoading = true }
        do {
            profile = try await CampusServiceClient.shared.fetchShowerProfile()
            if let profile { phone = profile.phone }
        } catch {
            if !silently { errorMessage = error.localizedDescription }
        }
        isLoading = false
    }

    @MainActor
    private func queryFee() async {
        isLoading = true
        errorMessage = nil
        do {
            let kind: HuiXinFeeKind = appState.campus == .hefei
                ? .bathingHefei(phone: phone.trimmed)
                : .bathingXuancheng(phone: phone.trimmed)
            feeResults = try await CampusServiceClient.shared.fetchFee(kind)
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }
}

struct LaundryServiceView: View {
    @EnvironmentObject private var appState: AppState
    @State private var locations: [LaundryLocation] = []
    @State private var category = "全部"
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingLogin = false

    private let categories = ["全部", "洗衣", "洗鞋", "烘干"]
    private var categoryCode: String? {
        switch category {
        case "洗衣": "00"
        case "洗鞋": "01"
        case "烘干": "02"
        default: nil
        }
    }

    var body: some View {
        List {
            Section {
                Picker("设备类型", selection: $category) {
                    ForEach(categories, id: \.self) { Text($0) }
                }
                .pickerStyle(.segmented)
            }
            if let errorMessage {
                Section { ContentUnavailableView("洗衣设备读取失败", systemImage: "washer", description: Text(errorMessage)) }
            }
            ForEach(locations) { location in
                Section(location.name) {
                    LabeledContent("空闲设备", value: "\(location.idleCount) 台")
                    LabeledContent("可预约", value: location.enableReserve ? "\(location.reserveNum) 台" : "不支持")
                    LabeledContent("地址", value: location.address)
                    LabeledContent("开放时间", value: location.workTime)
                }
            }
            Section("合肥校区官方充值") {
                if let url = CampusServiceClient.shared.savedHuiXinChargeURL(itemID: 26) {
                    NavigationLink("打开慧新易校洗衣入口") { PortalWebView(url: url) }
                } else {
                    Button("登录后打开充值入口") { showingLogin = true }
                }
            }
        }
        .navigationTitle("洗衣")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if isLoading { ProgressView("正在读取海乐设备…") } }
        .task(id: "\(appState.campus.rawValue)-\(category)") { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showingLogin) { NavigationStack { LoginPortalView() } }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            locations = try await CampusServiceClient.shared.fetchLaundryLocations(
                xuancheng: appState.campus == .xuancheng,
                categoryCode: categoryCode
            )
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }
}

struct SecondClassServiceView: View {
    @State private var activities: [SecondClassActivity] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingLogin = false

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    ContentUnavailableView("第二课堂读取失败", systemImage: "person.3.sequence", description: Text(errorMessage))
                    Button("前往安全登录", systemImage: "lock.shield") { showingLogin = true }
                }
            }
            ForEach(activities) { activity in
                NavigationLink {
                    PortalWebView(url: URL(string: "https://dekt.hfut.edu.cn/scReports/activity/item_detail/\(activity.id)")!)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(activity.name).font(.headline)
                        Text("\(activity.beginTime) ～ \(activity.endTime)")
                            .font(.caption).foregroundStyle(.secondary)
                        Text([activity.module, activity.form, activity.sponsor].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .navigationTitle("第二课堂")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if isLoading { ProgressView("正在读取第二课堂…") } }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showingLogin, onDismiss: { Task { await load() } }) {
            NavigationStack { LoginPortalView() }
        }
    }

    @MainActor
    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do { activities = try await CampusServiceClient.shared.fetchSecondClassActivities() }
        catch { errorMessage = error.localizedDescription }
        isLoading = false
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    var maskedPhone: String {
        guard count >= 7 else { return self }
        return String(prefix(3)) + "****" + String(suffix(4))
    }
}
