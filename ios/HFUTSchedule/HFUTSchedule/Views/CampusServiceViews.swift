import SwiftUI

struct CampusCardServiceView: View {
    @Environment(\.openURL) private var openURL
    @State private var cards: [HuiXinCard] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingLogin = false

    var body: some View {
        List {
            Section {
                Button("支付宝校园卡充值", systemImage: "arrow.up.forward.app.fill") {
                    openURL(CampusServiceClient.alipayCampusCardURL) { accepted in
                        if !accepted { openURL(CampusServiceClient.alipayCampusCardFallbackURL) }
                    }
                }
            } footer: {
                Text("与 Android 原版一致，优先直达支付宝校园卡充值页面。")
            }
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
    @AppStorage("electricityRegion") private var region = "11"
    @State private var buildings: [HuiXinSelectionOption] = []
    @State private var rooms: [HuiXinSelectionOption] = []
    @State private var results: [String: String] = [:]
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingLogin = false

    private var itemID: Int { appState.campus == .hefei ? 1 : 261 }

    var body: some View {
        List {
            Section("\(appState.campus.rawValue)寝室电费") {
                if appState.campus == .hefei {
                    Picker("楼栋", selection: $building) {
                        Text("请选择楼栋").tag("")
                        ForEach(buildings) { option in Text(option.name).tag(option.value) }
                    }
                    .onChange(of: building) { _, _ in
                        room = ""
                        Task { await loadRooms() }
                    }
                    Picker("房间", selection: $room) {
                        Text("请选择房间").tag("")
                        ForEach(rooms) { option in Text(option.name).tag(option.value) }
                    }
                } else {
                    Picker("楼栋", selection: $building) {
                        Text("请选择楼栋").tag("")
                        ForEach(1...10, id: \.self) { Text("\($0)号楼").tag(String($0)) }
                    }
                    Picker("房间", selection: $room) {
                        Text("请选择房间").tag("")
                        ForEach(Self.xuanchengRooms, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("电表区域", selection: $region) {
                        Text("南边照明").tag("11")
                        Text("南边空调").tag("12")
                        Text("北边照明").tag("21")
                        Text("北边空调").tag("22")
                    }
                }
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
        .task(id: appState.campus.rawValue) {
            if appState.campus == .hefei { await loadBuildings() }
        }
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
                : .electricXuancheng(room: "300\(building.trimmed)\(room.trimmed)\(region)")
            results = try await CampusServiceClient.shared.fetchFee(kind)
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    @MainActor
    private func loadBuildings() async {
        do {
            buildings = try await CampusServiceClient.shared.fetchHefeiElectricOptions()
            if !building.isEmpty { await loadRooms() }
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor
    private func loadRooms() async {
        guard !building.isEmpty else { rooms = []; return }
        do { rooms = try await CampusServiceClient.shared.fetchHefeiElectricOptions(building: building) }
        catch { errorMessage = error.localizedDescription }
    }

    private static let xuanchengRooms: [String] = {
        (1...6).flatMap { floor in
            (1...30).map { room in String(format: "%d%02d", floor, room) }
        }
    }()
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
        .task { await loadBalancesAutomatically() }
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
    private func loadBalancesAutomatically() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        var failures: [String] = []

        if CampusServiceClient.shared.hasSavedShowerCredentials {
            do {
                profile = try await CampusServiceClient.shared.fetchShowerProfile()
                if let profile { phone = profile.phone }
            } catch {
                failures.append("洗浴账户：\(error.localizedDescription)")
            }
        }

        let savedPhone = phone.trimmed
        if !savedPhone.isEmpty {
            do {
                let kind: HuiXinFeeKind = appState.campus == .hefei
                    ? .bathingHefei(phone: savedPhone)
                    : .bathingXuancheng(phone: savedPhone)
                feeResults = try await CampusServiceClient.shared.fetchFee(kind)
            } catch {
                failures.append("洗浴余额：\(error.localizedDescription)")
            }
        }

        errorMessage = failures.isEmpty ? nil : failures.joined(separator: "\n")
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
    @Environment(\.openURL) private var openURL
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
            Section("充值与支付") {
                Button("打开微信小程序支付", systemImage: "message.fill") {
                    openURL(URL(string: "weixin://")!)
                }
                Text("微信打开后搜索“海乐生活”或“智慧笑联”；设备支付必须在对应官方小程序内完成。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let url = CampusServiceClient.shared.savedHuiXinChargeURL(itemID: 26) {
                    NavigationLink("慧新易校洗衣充值") { PortalWebView(url: url) }
                }
            }
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
                    if location.enableReserve {
                        LabeledContent("可预约", value: "\(location.reserveNum)/\(location.idleCount) 台")
                    } else {
                        // Android labels idleCount as device count when this
                        // location does not support reservation.
                        LabeledContent("设备数", value: "\(location.idleCount) 台")
                    }
                    LabeledContent("地址", value: location.address)
                    LabeledContent("开放时间", value: location.workTime)
                    NavigationLink("查看各楼层设备与空闲状态") {
                        LaundryDeviceListView(location: location)
                    }
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

private struct LaundryDeviceListView: View {
    let location: LaundryLocation
    @Environment(\.openURL) private var openURL
    @State private var categoryCode = "00"
    @State private var devices: [LaundryDevice] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let categories = [("洗衣机", "00"), ("洗鞋机", "01"), ("烘干机", "02")]
    private var groupedDevices: [(String, [LaundryDevice])] {
        Dictionary(grouping: devices, by: \.floorText)
            .map { ($0.key, $0.value.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) }
            .sorted { lhs, rhs in lhs.0.localizedStandardCompare(rhs.0) == .orderedAscending }
    }

    var body: some View {
        List {
            Section {
                Button("打开微信小程序支付", systemImage: "message.fill") { openURL(URL(string: "weixin://")!) }
                Picker("设备类型", selection: $categoryCode) {
                    ForEach(categories, id: \.1) { Text($0.0).tag($0.1) }
                }
                .pickerStyle(.segmented)
            }
            if let errorMessage { ContentUnavailableView("设备读取失败", systemImage: "washer", description: Text(errorMessage)) }
            ForEach(groupedDevices, id: \.0) { floor, floorDevices in
                Section("\(floor) · 空闲 \(floorDevices.filter { $0.state == 1 && $0.finishDate == nil }.count)/\(floorDevices.count)") {
                    ForEach(floorDevices) { device in
                        HStack(spacing: 12) {
                            Image(systemName: device.state == 1 ? "checkmark.circle.fill" : (device.state == 2 ? "timer" : "exclamationmark.triangle.fill"))
                                .foregroundStyle(device.state == 1 ? .green : (device.state == 2 ? .orange : .red))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(device.name).font(.headline)
                                if let remaining = device.remainingUsageText {
                                    Text(remaining).font(.caption).foregroundStyle(.secondary)
                                    if let finishTime = device.finishTime {
                                        Text("预计 \(finishTime) 完成").font(.caption2).foregroundStyle(.tertiary)
                                    }
                                } else if device.enableReserve {
                                    Text("可预约 \(device.reserveNum) 台").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(device.stateText).font(.subheadline.weight(.semibold))
                        }
                    }
                }
            }
            if devices.allSatisfy({ $0.state == 3 && $0.finishTime == nil }), !devices.isEmpty {
                Section {
                    Label("海乐公开接口中该场所的设备全部处于离线/故障状态，无法推断真实空闲情况。", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(location.name)
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if isLoading { ProgressView("正在读取设备…") } }
        .task(id: categoryCode) { await load() }
        .refreshable { await load() }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        do { devices = try await CampusServiceClient.shared.fetchLaundryDevices(positionID: location.id, categoryCode: categoryCode) }
        catch { errorMessage = error.localizedDescription }
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
