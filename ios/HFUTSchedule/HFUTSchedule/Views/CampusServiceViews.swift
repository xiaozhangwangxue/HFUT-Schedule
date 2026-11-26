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
            Section("账单与统计") {
                AppNavigationLink("消费流水与日期范围") { CampusCardBillsView() }
                AppNavigationLink("消费分析与预测") { CampusCardAnalysisView() }
                Button("使用已配置的一卡通密码登录") { Task { await passwordLogin() } }.disabled(isLoading)
            }
            Section("官方入口") {
                if let url = CampusServiceClient.shared.savedHuiXinPortalURL() {
                    AppNavigationLink("余额、账单、充值与卡管理") { PortalWebView(url: url) }
                } else {
                    Button("登录后打开完整一卡通", systemImage: "key") { showingLogin = true }
                }
                if let url = CampusServiceClient.shared.savedHuiXinPortalURL(path: "plat/pay") {
                    AppNavigationLink("付款码") { PortalWebView(url: url) }
                }
            }
        }
        .navigationTitle("一卡通")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if isLoading { ProgressView("正在读取一卡通…") } }
        .task { await load() }
        .refreshable { await load(forceRefresh: true) }
        .sheet(isPresented: $showingLogin, onDismiss: { Task { await load() } }) {
            AppNavigationStack { LoginPortalView() }
        }
    }

        @MainActor private func passwordLogin() async {
        isLoading = true; errorMessage = nil
        do { try await CampusServiceClient.shared.loginHuiXinWithConfiguredPassword(); cards = try await CampusServiceClient.shared.fetchCampusCards() }
        catch { AcademicServiceDiagnostics.record(context: "校园生活服务", error: error); errorMessage = error.localizedDescription }
        isLoading = false
    }

@MainActor
    private func load(forceRefresh: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do { cards = try await CampusServiceClient.shared.fetchCampusCards(forceRefresh: forceRefresh) }
        catch { AcademicServiceDiagnostics.record(context: "校园生活服务", error: error); errorMessage = error.localizedDescription }
        isLoading = false
    }
}

@MainActor
struct ElectricityServiceView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var model: ElectricityQueryModel
    @State private var showingLogin = false

    init() { _model = StateObject(wrappedValue: ElectricityQueryModel()) }
    init(model: ElectricityQueryModel) { _model = StateObject(wrappedValue: model) }

    private var selectedCampus: ElectricityCampus { appState.campus == .hefei ? .hefei : .xuancheng }

    var body: some View {
        List {
            Section {
                if model.campus == .hefei {
                    Picker("宿舍楼与区域", selection: Binding(get: { model.dormitoryBuildingID }, set: { model.setDormitoryBuilding($0) })) {
                        Text("请选择宿舍楼").tag("")
                        if !model.dormitoryBuildingID.isEmpty, !model.dormitoryBuildings.contains(where: { $0.value == model.dormitoryBuildingID }) {
                            Text("已保存宿舍楼").tag(model.dormitoryBuildingID)
                        }
                        ForEach(model.dormitoryBuildings) { option in Text(option.name).tag(option.value) }
                    }
                    Picker("房间", selection: Binding(get: { model.dormitoryRoomID }, set: { model.setDormitoryRoom($0) })) {
                        Text("请选择房间").tag("")
                        if !model.dormitoryRoomID.isEmpty, !model.dormitoryRooms.contains(where: { $0.value == model.dormitoryRoomID }) {
                            Text("已保存房间").tag(model.dormitoryRoomID)
                        }
                        ForEach(model.dormitoryRooms) { option in Text(option.name).tag(option.value) }
                    }
                } else {
                    Picker("宿舍楼", selection: Binding(get: { model.selection.building }, set: model.setBuilding)) {
                        Text("请选择宿舍楼").tag("")
                        ForEach(1...10, id: \.self) { Text("\($0)号楼").tag(String($0)) }
                    }
                    Picker("房间", selection: Binding(get: { model.selection.room }, set: model.setRoom)) {
                        Text("请选择房间").tag("")
                        ForEach(Self.xuanchengRooms, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("宿舍区域", selection: Binding(get: { model.selection.side }, set: model.setSide)) {
                        ForEach(ElectricityDormitory.Side.allCases) { Text($0.title).tag($0) }
                    }
                }
                if model.isLoadingOptions { ProgressView("正在读取楼栋与房间…") }
                Button(model.savedSelection == nil ? "保存默认宿舍并查询" : "更新默认宿舍并查询", systemImage: "house.fill") {
                    model.saveAndQuery()
                }
                .disabled(!model.canSave)
                Button("刷新电费", systemImage: "arrow.clockwise") { model.refreshSaved() }
                    .disabled(!model.canRefresh)
                if model.hasUnsavedChanges, model.savedSelection != nil {
                    Button("恢复已保存的宿舍") { model.restoreSaved() }
                }
            } header: {
                Text("\(model.campus.title) · 默认宿舍")
            } footer: {
                if model.campus == .xuancheng {
                    Text("保存宿舍楼、房间和南／北区域后，下次进入本页会自动查询该宿舍的照明与空调电费。")
                } else {
                    Text("宿舍楼和房间只需选择一次，程序会自动匹配校方的照明与空调电表编码并分别查询。校方未提供对应电表时会单独提示。")
                }
            }
            .disabled(model.isLoadingOptions)

            ForEach(model.results) { result in
                Section(result.title) {
                    if result.isLoading { ProgressView("正在查询…") }
                    if result.needsConfiguration {
                        Text("未匹配到该宿舍的此类电表，请刷新校方列表或重新选择宿舍。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(result.values.keys.sorted(), id: \.self) { key in
                        LabeledContent(key, value: result.values[key] ?? "")
                    }
                    if let error = result.error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else if !result.isLoading && !result.needsConfiguration && result.values.isEmpty {
                        Text("校方未返回可展示的电费项目。").foregroundStyle(.secondary)
                    }
                }
            }
            if let error = model.optionsError {
                Section("楼栋与房间列表读取失败") {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                    Button("重新读取列表") { model.reloadAfterLogin() }
                }
            }
            if model.hasError {
                Section {
                    Button("前往安全登录", systemImage: "lock.shield") { showingLogin = true }
                }
            }
            Section("官方缴费") {
                if let url = CampusServiceClient.shared.savedHuiXinChargeURL(itemID: model.campus.feeItemID) {
                    AppNavigationLink("打开慧新易校电费入口") { PortalWebView(url: url) }
                } else {
                    Button("登录后打开缴费入口") { showingLogin = true }
                }
            }
        }
        .navigationTitle("宿舍电费")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: selectedCampus) { model.activate(campus: selectedCampus) }
        .onDisappear { model.deactivate() }
        .sheet(isPresented: $showingLogin, onDismiss: { model.reloadAfterLogin() }) {
            AppNavigationStack { LoginPortalView() }
        }
    }

    private static let xuanchengRooms: [String] = {
        (1...6).flatMap { floor in (1...30).map { room in String(format: "%d%02d", floor, room) } }
    }()
}

struct CampusNetworkServiceView: View {
    var body: some View { NativeSchoolNetworkView() }
}

struct BathingServiceView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var studentStore: AcademicStudentStore
    @AppStorage("bathingPhone") private var phone = ""
    @State private var password = ""
    @State private var alternativeLoginCode = ""
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
                    AppNavigationLink("花洒设备与使用码") { ShowerControlView() }
                    AppNavigationLink("洗浴消费账单") { ShowerBillsView() }
                }
            } else {
                Section {
                    TextField("手机号", text: $phone).keyboardType(.phonePad)
                    SecureField("洗浴平台密码", text: $password)
                    DisclosureGroup("使用已有 loginCode 登录") {
                        SecureField("已有 loginCode", text: $alternativeLoginCode)
                        Button("验证并保存 loginCode") { Task { await loginByCode() } }.disabled(phone.trimmed.isEmpty || alternativeLoginCode.isEmpty || isLoading)
                    }
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
                if let value = StudentPhone.from(studentStore.info) { Button("使用个人信息中的手机号") { phone = value } }
                Button("查询洗浴余额", systemImage: "shower") { Task { await queryFee() } }
                    .disabled(phone.trimmed.isEmpty || isLoading)
                ForEach(feeResults.keys.sorted(), id: \.self) { key in
                    LabeledContent(key, value: feeResults[key] ?? "")
                }
                if let url = CampusServiceClient.shared.savedHuiXinChargeURL(itemID: itemID) {
                    AppNavigationLink("打开官方充值入口") { PortalWebView(url: url) }
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
        .task {
            if StudentPhone.from(studentStore.info) == nil { await studentStore.refresh() }
            guard !Task.isCancelled else { return }
            phone = await studentStore.phoneForLifeServices() ?? phone
            await loadBalancesAutomatically()
        }
        .refreshable { await loadBalancesAutomatically() }
        .sheet(isPresented: $showingLogin) { AppNavigationStack { LoginPortalView() } }
    }

    @MainActor private func loginByCode() async {
        isLoading = true; errorMessage = nil; defer { isLoading = false }
        do { profile = try await CampusServiceClient.shared.loginShowerWithCode(phone: phone.trimmed, loginCode: alternativeLoginCode); alternativeLoginCode = "" }
        catch { AcademicServiceDiagnostics.record(context: "校园生活服务", error: error); errorMessage = error.localizedDescription }
    }

    @MainActor
    private func loginShower() async {
        isLoading = true
        errorMessage = nil
        do {
            profile = try await CampusServiceClient.shared.loginShower(phone: phone.trimmed, password: password)
            password = ""
        } catch { AcademicServiceDiagnostics.record(context: "校园生活服务", error: error); errorMessage = error.localizedDescription }
        isLoading = false
    }

    @MainActor
    private func loadProfile(silently: Bool = false) async {
        if !silently { isLoading = true }
        do {
            profile = try await CampusServiceClient.shared.fetchShowerProfile()
            if let profile, phone.trimmed.isEmpty { phone = profile.phone }
        } catch { AcademicServiceDiagnostics.record(context: "校园生活服务", error: error);
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
                if let profile, phone.trimmed.isEmpty { phone = profile.phone }
            } catch { AcademicServiceDiagnostics.record(context: "校园生活服务", error: error);
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
            } catch { AcademicServiceDiagnostics.record(context: "校园生活服务", error: error);
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
        } catch { AcademicServiceDiagnostics.record(context: "校园生活服务", error: error); errorMessage = error.localizedDescription }
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
            if appState.campus == .hefei { HuiXinLaundryBalanceSection() }
            Section("充值与支付") {
                Button("打开微信小程序支付", systemImage: "message.fill") {
                    openURL(URL(string: "weixin://")!)
                }
                Text("微信打开后搜索“海乐生活”；设备支付在官方小程序内完成。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if appState.campus == .hefei {
                    AppNavigationLink("慧新易校洗衣缴费") { HuiXinLaundryChargeView() }
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
                    AppNavigationLink("查看各楼层设备与空闲状态") {
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
        .sheet(isPresented: $showingLogin) { AppNavigationStack { LoginPortalView() } }
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
        } catch { AcademicServiceDiagnostics.record(context: "校园生活服务", error: error); errorMessage = error.localizedDescription }
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
        catch { AcademicServiceDiagnostics.record(context: "校园生活服务", error: error); errorMessage = error.localizedDescription }
        isLoading = false
    }
}

struct SecondClassServiceView: View {
    @State private var page = 1
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
                AppNavigationLink {
                    SecondClassActivityDetailView(activity: activity)
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
        .safeAreaInset(edge: .bottom) { AcademicPageControls(page: $page, loading: isLoading).padding().background(.regularMaterial) }
        .onChange(of: page) { _, _ in Task { await load() } }
        .navigationTitle("第二课堂")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if isLoading { ProgressView("正在读取第二课堂…") } }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showingLogin, onDismiss: { Task { await load() } }) {
            AppNavigationStack { LoginPortalView() }
        }
    }

    @MainActor
    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do { activities = try await CampusServiceClient.shared.fetchSecondClassActivities(page: page) }
        catch { AcademicServiceDiagnostics.record(context: "校园生活服务", error: error); errorMessage = error.localizedDescription }
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
