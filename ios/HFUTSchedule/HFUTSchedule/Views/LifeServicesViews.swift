import SwiftUI
import Charts
import UIKit
import VisionKit

struct CampusCardBillsView: View {
    @State private var page = 1
    @State private var query = ""
    @State private var records: [CampusCardBill] = []
    @State private var total = 0
    @State private var loading = false
    @State private var error: String?
    @State private var from = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var to = Date()
    @State private var range: CampusCardRangeTotal?
    var body: some View {
        List {
            Section("关键词") {
                TextField("商户、类型或流水信息", text: $query)
                Button("查询账单") { page = 1; Task { await load() } }.disabled(loading)
            }
            Section("日期范围合计") {
                DatePicker("开始", selection: $from, displayedComponents: .date)
                DatePicker("结束", selection: $to, in: from..., displayedComponents: .date)
                Button("查询范围支出") { Task { await rangeTotal() } }.disabled(loading)
                if let range { LabeledContent("支出", value: range.expenses.formatted(.currency(code: "CNY"))); LabeledContent("收入", value: range.income.formatted(.currency(code: "CNY"))) }
            }
            if let error { Text(error).foregroundStyle(.red) }
            Section("消费流水（共 \(total) 笔）") {
                ForEach(records) { bill in
                    AppNavigationLink { CampusCardBillDetailView(bill: bill) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) { Text(bill.resume); Text("\(bill.jndatetimeStr) · \(bill.turnoverType)").font(.caption).foregroundStyle(.secondary) }
                            Spacer(); Text(bill.amount.formatted(.currency(code: "CNY"))).monospacedDigit()
                        }
                    }
                }
            }
            AcademicPageControls(page: $page, loading: loading)
        }
        .navigationTitle("一卡通账单")
        .task(id: page) { await load() }.refreshable { await load() }
        .overlay { if loading { ProgressView() } }
    }
    @MainActor private func load() async {
        guard !loading else { return }; loading = true; error = nil; defer { loading = false }
        do { let result = try await CampusServiceClient.shared.fetchCampusCardBills(page: page, keyword: query); records = result.records; total = result.total }
        catch { AcademicServiceDiagnostics.record(context: "生活服务操作", error: error); self.error = error.localizedDescription }
    }
    @MainActor private func rangeTotal() async {
        loading = true; error = nil; defer { loading = false }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        do { range = try await CampusServiceClient.shared.fetchCampusCardRange(from: formatter.string(from: from) + " 00:00:00", to: formatter.string(from: to) + " 23:59:59") }
        catch { AcademicServiceDiagnostics.record(context: "生活服务操作", error: error); self.error = error.localizedDescription }
    }
}
private struct CampusCardBillDetailView: View {
    let bill: CampusCardBill
    var body: some View {
        List {
            LabeledContent("交易信息", value: bill.resume)
            LabeledContent("金额", value: bill.amount.formatted(.currency(code: "CNY")))
            LabeledContent("类型", value: bill.turnoverType)
            LabeledContent("交易时间", value: bill.jndatetimeStr)
            LabeledContent("记账日期", value: bill.effectdateStr)
            LabeledContent("来源账户", value: bill.fromAccount)
            LabeledContent("流水号", value: bill.orderId)
        }.navigationTitle("交易详情").textSelection(.enabled)
    }
}

struct CampusCardAnalysisView: View {
    @State private var analysis: CampusCardForecast?
    @State private var loading = false
    @State private var error: String?
    @State private var month = Date()
    @State private var daily: [String: Double] = [:]
    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            if let analysis {
                Section("消费预测") {
                    LabeledContent("日平均", value: analysis.dailyAverage.formatted(.currency(code: "CNY")))
                    LabeledContent("明日预计", value: analysis.nextDay?.formatted(.currency(code: "CNY")) ?? "数据不足")
                    if let r2 = analysis.dailyR2 { LabeledContent("日拟合 R²", value: r2.formatted(.number.precision(.fractionLength(3)))) }
                    LabeledContent("月平均", value: analysis.monthlyAverage.formatted(.currency(code: "CNY")))
                    LabeledContent("下月预计", value: analysis.nextMonth?.formatted(.currency(code: "CNY")) ?? "数据不足")
                    if let r2 = analysis.monthlyR2 { LabeledContent("月拟合 R²", value: r2.formatted(.number.precision(.fractionLength(3)))) }
                    Text("采用原版的异常值剔除及线性拟合；不把宿舍电费计入个人消费预测。").font(.caption).foregroundStyle(.secondary)
                }
                Section("月消费趋势") { amountChart(analysis.monthlyAmounts) }
                Section("消费地点") {
                    ForEach(analysis.merchants.keys.sorted { (analysis.merchants[$0] ?? 0) > (analysis.merchants[$1] ?? 0) }, id: \.self) { name in
                        LabeledContent(name, value: (analysis.merchants[name] ?? 0).formatted(.currency(code: "CNY")))
                    }
                }
            }
            Section("官方每日支出") {
                DatePicker("查询月份", selection: $month, displayedComponents: .date)
                Button("查询该月每日支出") { Task { await monthly() } }.disabled(loading)
                if !daily.isEmpty { amountChart(daily); LabeledContent("合计", value: daily.values.reduce(0, +).formatted(.currency(code: "CNY"))) }
                ForEach(daily.keys.sorted(by: >), id: \.self) { date in LabeledContent(date, value: (daily[date] ?? 0).formatted(.currency(code: "CNY"))) }
            }
        }
        .navigationTitle("消费分析")
        .task { await load() }.refreshable { await load() }
        .overlay { if loading { ProgressView("正在读取完整账单…") } }
    }
    private func amountChart(_ values: [String: Double]) -> some View {
        Chart(values.keys.sorted(), id: \.self) { date in BarMark(x: .value("日期", date), y: .value("金额", values[date] ?? 0)).foregroundStyle(AppTheme.accent) }.frame(height: 190)
    }
    @MainActor private func load() async {
        loading = true; error = nil; defer { loading = false }
        do { analysis = CampusCardAnalysis.forecast(try await CampusServiceClient.shared.fetchAllCampusCardBills()) }
        catch { AcademicServiceDiagnostics.record(context: "生活服务操作", error: error); self.error = error.localizedDescription }
    }
    @MainActor private func monthly() async {
        loading = true; error = nil; defer { loading = false }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM"
        do { daily = try await CampusServiceClient.shared.fetchCampusCardMonthlyAmounts(month: formatter.string(from: month)) }
        catch { AcademicServiceDiagnostics.record(context: "生活服务操作", error: error); self.error = error.localizedDescription }
    }
}

struct NativeSchoolNetworkView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage(AppSettingsKey.xuanchengQuota) private var quota = AppSettingsDefaults.xuanchengQuota
    @State private var status: SchoolNetworkStatus?
    @State private var message: String?
    @State private var loading = false
    @State private var results: [String: String] = [:]
    private var xuancheng: Bool { appState.campus == .xuancheng }
    var body: some View {
        List {
            Section("原生校园网操作") {
                Button("登录当前校区校园网", systemImage: "wifi") { Task { await action(0) } }.disabled(loading)
                Button("注销校园网", systemImage: "wifi.slash") { Task { await action(1) } }.disabled(loading)
                Button("读取网关状态", systemImage: "arrow.clockwise") { Task { await action(2) } }.disabled(loading)
                Button("测试外网连通性", systemImage: "network") { Task { await action(3) } }.disabled(loading)
            }
            if let status {
                Section("网关实时信息") {
                    LabeledContent("网关", value: status.gateway)
                    LabeledContent("已用流量", value: "\((status.usedMB / 1024).formatted(.number.precision(.fractionLength(2)))) GiB")
                    LabeledContent("余额", value: status.fee.formatted(.currency(code: "CNY")))
                    if xuancheng && quota > 0 {
                        LabeledContent("月额度", value: "\(quota.formatted()) GiB")
                        ProgressView(value: min(1, status.usedMB / (1024 * quota)))
                        LabeledContent("已用比例", value: (status.usedMB / (1024 * quota)).formatted(.percent.precision(.fractionLength(1))))
                        LabeledContent("剩余额度", value: "\(max(0, quota - status.usedMB / 1024).formatted(.number.precision(.fractionLength(2)))) GiB")
                    }
                    Text(status.updatedAt.formatted(date: .abbreviated, time: .standard)).font(.caption).foregroundStyle(.secondary)
                }
            }
            if let message { Section { Text(message).textSelection(.enabled) } }
            Section("用量统计") { AppNavigationLink("历史月费与学期用量") { SchoolNetworkHistoryView() } }
            if xuancheng {
                Section("慧新校园网账户") {
                    Button("读取账户余额和流量") { Task { await huiXin() } }.disabled(loading)
                    ForEach(results.keys.sorted(), id: \.self) { key in LabeledContent(key, value: results[key] ?? "") }
                }
            }
            Section("官方页面") {
                ForEach(SchoolNetworkClient.gateways(xuancheng: xuancheng), id: \.absoluteString) { url in AppNavigationLink(url.host ?? "网关") { PortalWebView(url: url) } }
                AppNavigationLink("自服务页面") { PortalWebView(url: URL(string: "https://xywzz.hfut.edu.cn:8443/Self/LoginAction.action")!) }
            }
        }
        .navigationTitle("校园网")
        .overlay { if loading { ProgressView() } }
        .task { if let data = UserDefaults.standard.data(forKey: "nativeSchoolNetworkStatus") { status = try? JSONDecoder().decode(SchoolNetworkStatus.self, from: data) } }
    }
    @MainActor private func action(_ kind: Int) async {
        loading = true; message = nil; defer { loading = false }
        do {
            switch kind {
            case 0: message = try await SchoolNetworkClient.shared.login(xuancheng: xuancheng); status = try? await SchoolNetworkClient.shared.status(xuancheng: xuancheng)
            case 1: message = try await SchoolNetworkClient.shared.logout(xuancheng: xuancheng); status = nil
            case 2: status = try await SchoolNetworkClient.shared.status(xuancheng: xuancheng)
            default: message = try await SchoolNetworkClient.shared.connectivity() ? "外网连通测试成功" : "未通过外网连通测试"
            }
        } catch { AcademicServiceDiagnostics.record(context: "生活服务操作", error: error); message = error.localizedDescription }
    }
    @MainActor private func huiXin() async {
        loading = true; defer { loading = false }
        do { results = try await CampusServiceClient.shared.fetchFee(.networkXuancheng) } catch { AcademicServiceDiagnostics.record(context: "生活服务操作", error: error); message = error.localizedDescription }
    }
}

struct SchoolNetworkHistoryView: View {
    @EnvironmentObject private var appState: AppState
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var records: [SchoolNetworkMonthRecord] = []
    @State private var from = Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date()
    @State private var to = Date()
    @State private var loading = false
    @State private var error: String?
    private var filtered: [SchoolNetworkMonthRecord] {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        let low = formatter.string(from: from), high = formatter.string(from: to)
        return records.filter { String($0.startDate.prefix(10)) <= high && String($0.endDate.prefix(10)) >= low }
    }
    var body: some View {
        List {
            Section("查询年份") { Stepper(year.formatted(.number.grouping(.never)), value: $year, in: 2000...2100); Button("查询月账单") { Task { await load() } }.disabled(loading) }
            Section("学期或日期范围汇总") {
                DatePicker("开始", selection: $from, displayedComponents: .date)
                DatePicker("结束", selection: $to, in: from..., displayedComponents: .date)
                Button("查询该日期范围") { Task { await loadRange() } }.disabled(loading)
                LabeledContent("总流量", value: "\((filtered.reduce(0) { $0 + $1.flowMB } / 1024).formatted(.number.precision(.fractionLength(2)))) GiB")
                LabeledContent("总时长", value: "\(filtered.reduce(0) { $0 + $1.durationMinutes }) 分钟")
                LabeledContent("总费用", value: filtered.reduce(0) { $0 + $1.baseFee + $1.usageFee }.formatted(.currency(code: "CNY")))
            }
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(records) { record in
                Section("\(record.startDate) 至 \(record.endDate)") {
                    LabeledContent("套餐", value: record.packageName)
                    LabeledContent("基本费", value: record.baseFee.formatted(.currency(code: "CNY")))
                    LabeledContent("用量费", value: record.usageFee.formatted(.currency(code: "CNY")))
                    LabeledContent("时长", value: "\(record.durationMinutes) 分钟")
                    LabeledContent("流量", value: "\(record.flowMB.formatted()) MB")
                    LabeledContent("账单时间", value: record.billTime)
                }
            }
        }
        .navigationTitle("校园网历史用量")
        .overlay { if loading { ProgressView() } }
        .task { await load() }.refreshable { await load() }
    }
    @MainActor private func loadRange() async {
        loading = true; error = nil; defer { loading = false }
        do { records = try await SchoolNetworkClient.shared.history(from: from, to: to, xuancheng: appState.campus == .xuancheng) }
        catch { AcademicServiceDiagnostics.record(context: "生活服务操作", error: error); self.error = error.localizedDescription }
    }
    @MainActor private func load() async {
        loading = true; error = nil; defer { loading = false }
        do { records = try await SchoolNetworkClient.shared.history(year: year, xuancheng: appState.campus == .xuancheng) }
        catch { AcademicServiceDiagnostics.record(context: "生活服务操作", error: error); self.error = error.localizedDescription }
    }
}

private struct SavedShowerDevice: Identifiable, Codable {
    var id = UUID()
    var name: String
    var code: String
}
struct ShowerControlView: View {
    @State private var devices: [SavedShowerDevice] = []
    @State private var deviceCode = ""
    @State private var deviceName = ""
    @State private var useCode: String?
    @State private var password = ""
    @State private var newCode = ""
    @State private var message: String?
    @State private var loading = false
    @State private var confirmStart = false
    @State private var confirmReset = false
    @State private var showingScanner = false
    var body: some View {
        List {
            Section("花洒设备") {
                TextField("MAC/设备编码", text: $deviceCode).textInputAutocapitalization(.characters)
                Button("扫描花洒二维码", systemImage: "qrcode.viewfinder") { showingScanner = true }.disabled(loading)
                TextField("设备备注", text: $deviceName)
                Button("保存设备") {
                    guard let code = ShowerDeviceCode.normalized(deviceCode) else { return }
                    deviceCode = code
                    let existing = devices.firstIndex { $0.code == code }
                    if let existing { devices[existing].name = deviceName } else { devices.append(SavedShowerDevice(name: deviceName, code: code)) }
                    persist()
                }.disabled(ShowerDeviceCode.normalized(deviceCode) == nil)
                if !deviceCode.isEmpty && ShowerDeviceCode.normalized(deviceCode) == nil { Text("MAC地址需为12位十六进制字符。").font(.caption).foregroundStyle(.secondary) }
                Button("开始洗浴") { confirmStart = true }.disabled(ShowerDeviceCode.normalized(deviceCode) == nil || loading)
            }
            Section("已保存的花洒") {
                ForEach(devices) { device in Button { deviceCode = device.code; deviceName = device.name } label: { VStack(alignment: .leading) { Text(device.name.isEmpty ? "花洒" : device.name); Text(device.code).font(.caption.monospacedDigit()) } } }
                    .onDelete { devices.remove(atOffsets: $0); persist() }
            }
            Section("使用码") {
                if let useCode { Text("*****\(useCode)").font(.title.monospacedDigit()).textSelection(.enabled) }
                Button("读取/刷新使用码") { Task { await loadCode() } }.disabled(loading)
                SecureField("洗浴平台密码", text: $password)
                SecureField("新使用码（5位数字）", text: $newCode).keyboardType(.numberPad)
                Button("修改使用码") { confirmReset = true }.disabled(loading || password.isEmpty || newCode.count != 5)
            }
            if let message { Section("平台返回") { Text(message).textSelection(.enabled) } }
        }
        .navigationTitle("花洒与使用码")
        .task { if let data = UserDefaults.standard.data(forKey: "savedShowerDevices") { devices = (try? JSONDecoder().decode([SavedShowerDevice].self, from: data)) ?? [] }; await loadCode() }
        .overlay { if loading { ProgressView() } }
        .sheet(isPresented: $showingScanner) { AppNavigationStack { ShowerDeviceScannerSheet(deviceCode: $deviceCode) } }
        .confirmationDialog("确认启动此花洒？", isPresented: $confirmStart, titleVisibility: .visible) { Button("确认开始") { Task { await start() } } }
        .confirmationDialog("确认修改使用码？", isPresented: $confirmReset, titleVisibility: .visible) { Button("确认修改") { Task { await reset() } } }
    }
    private func persist() { if let data = try? JSONEncoder().encode(devices) { UserDefaults.standard.set(data, forKey: "savedShowerDevices") } }
    @MainActor private func loadCode() async {
        loading = true; defer { loading = false }
        do { useCode = try await CampusServiceClient.shared.showerUseCode() } catch { AcademicServiceDiagnostics.record(context: "生活服务操作", error: error); message = error.localizedDescription }
    }
    @MainActor private func start() async {
        loading = true; defer { loading = false }
        do { message = try await CampusServiceClient.shared.startShower(deviceCode: deviceCode).message } catch { AcademicServiceDiagnostics.record(context: "生活服务操作", error: error); message = error.localizedDescription }
    }
    @MainActor private func reset() async {
        loading = true; defer { loading = false; password = "" }
        do { let result = try await CampusServiceClient.shared.resetShowerUseCode(password: password, securityCode: newCode); message = result.message; if result.success { newCode = ""; useCode = try await CampusServiceClient.shared.showerUseCode() } } catch { AcademicServiceDiagnostics.record(context: "生活服务操作", error: error); message = error.localizedDescription }
    }
}

private struct ShowerDeviceScannerSheet: View {
    @Binding var deviceCode: String
    @Environment(\.dismiss) private var dismiss
    @State private var scannedValue: String?
    @State private var error: String?
    var body: some View {
        ZStack(alignment: .bottom) {
            if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                DataScannerRepresentable(scannedValue: $scannedValue)
            } else {
                ContentUnavailableView("实时扫码暂不可用", systemImage: "camera.badge.ellipsis", description: Text("请允许相机访问，或手动输入二维码贴纸下的MAC地址。"))
            }
            if let error {
                VStack { Text(error); Button("重新扫描") { self.error = nil; scannedValue = nil } }.padding().background(.regularMaterial).clipShape(RoundedRectangle(cornerRadius: 16)).padding()
            }
        }
        .navigationTitle("扫描花洒")
        .toolbar { Button("取消") { dismiss() } }
        .onChange(of: scannedValue) { _, value in
            guard let value else { return }
            if let code = ShowerDeviceCode.fromQRCode(value) { deviceCode = code; dismiss() }
            else { error = "未识别到有效花洒二维码，请扫描含KLCXKJ-Water的设备贴纸。" }
        }
    }
}

struct ShowerBillsView: View {
    @State private var page = 1
    @State private var records: [ShowerBill] = []
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(records) { bill in
                VStack(alignment: .leading, spacing: 5) {
                    Text(bill.description).font(.headline)
                    Text("\(bill.dealDate) · \(bill.dealMark)").font(.caption).foregroundStyle(.secondary)
                    if let spent = bill.xfMoney { LabeledContent("扣费", value: spent.formatted(.currency(code: "CNY"))) }
                    if let paid = bill.dealMoney { LabeledContent("处理金额", value: paid.formatted(.currency(code: "CNY"))) }
                }.padding(.vertical, 4)
            }
            AcademicPageControls(page: $page, loading: loading)
        }
        .navigationTitle("洗浴账单")
        .task(id: page) { await load() }.refreshable { await load() }
        .overlay { if loading { ProgressView() } }
    }
    @MainActor private func load() async { loading = true; error = nil; defer { loading = false }; do { records = try await CampusServiceClient.shared.showerBills(page: page) } catch { AcademicServiceDiagnostics.record(context: "生活服务操作", error: error); self.error = error.localizedDescription } }
}

struct HuiXinLaundryChargeView: View {
    var body: some View { HuiXinFeeChargeView(itemID: 26, title: "慧新洗衣缴费") }
}

struct HuiXinFeeChargeView: View {
    @EnvironmentObject private var studentStore: AcademicStudentStore
    let itemID: Int
    let title: String
    @State private var url: URL?
    @State private var error: String?
    @State private var phone: String?
    var body: some View {
        Group {
            if let url { PortalWebView(url: url, huiXinPhoneAutofill: HuiXinPhoneAutofill(phone: phone, itemID: itemID, url: url)) }
            else if let error {
                ContentUnavailableView {
                    Label("充值页面打开失败", systemImage: "exclamationmark.triangle")
                } description: { Text(error) } actions: {
                    Button("重新打开") { Task { await load() } }
                }
            } else { ProgressView().accessibilityLabel("正在打开官方充值页") }
        }
        .navigationTitle(title)
        .task(id: "\(itemID)|\(studentStore.info?.studentID ?? "")") { await load() }
        .task(id: "\(itemID)|\(studentStore.info?.studentID ?? "")") { await loadPhone() }
    }
    @MainActor private func loadPhone() async {
        phone = nil
        guard HuiXinPhoneAutofill.feeItemIDs.contains(itemID) else { return }
        #if DEBUG
        if AppUIPreview.enabled { phone = AppUIPreview.phone; return }
        #endif
        if let value = StudentPhone.from(studentStore.info) { phone = value; return }
        if studentStore.info == nil { await studentStore.refresh() }
        let value = await studentStore.phoneForLifeServices()
        guard !Task.isCancelled else { return }
        phone = value
    }
    @MainActor private func load() async {
        error = nil; url = nil
        #if DEBUG
        // The simulator fixture captures the loading state without requesting
        // an account-specific payment URL. Release always uses the real flow.
        if AppUIPreview.enabled { return }
        #endif
        do {
            let value = try await CampusServiceClient.shared.huiXinChargeURL(itemID: itemID)
            guard !Task.isCancelled else { return }
            url = value
        }
        catch {
            guard !Task.isCancelled else { return }
            AcademicServiceDiagnostics.record(context: "官方充值入口", error: error)
            self.error = error.localizedDescription
        }
    }
}

struct SecondClassActivityDetailView: View {
    let activity: SecondClassActivity
    var body: some View {
        List {
            if let url = URL(string: activity.activePhoto), url.scheme?.hasPrefix("http") == true { AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: { ProgressView() } }
            Section(activity.name) {
                LabeledContent("开始时间", value: activity.beginTime)
                LabeledContent("结束时间", value: activity.endTime)
                LabeledContent("活动模块", value: activity.module)
                LabeledContent("活动形式", value: activity.form)
                LabeledContent("主办单位", value: activity.sponsor)
                LabeledContent("人数", value: "\(activity.peopleNum)")
                LabeledContent("校区", value: activity.campus == 1 ? "合肥" : activity.campus == 2 ? "宣城" : "\(activity.campus)")
                if let speaker = activity.keynoteSpeaker { LabeledContent("主讲人", value: speaker) }
                if let venue = activity.theVenue { LabeledContent("地点", value: venue) }
            }
            AppNavigationLink("打开官方完整活动页面") { PortalWebView(url: URL(string: "https://dekt.hfut.edu.cn/scReports/activity/item_detail/\(activity.id)")!) }
        }.navigationTitle("活动详情").textSelection(.enabled)
    }
}
