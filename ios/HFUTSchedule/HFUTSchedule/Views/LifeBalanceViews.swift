import SwiftUI

struct HuiXinLaundryBalanceSection: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var studentStore: AcademicStudentStore
    @AppStorage("laundryPhone") private var phone = ""
    @StateObject private var model = PhoneFeeBalanceModel(service: .laundry)
    var body: some View {
        Section("慧新易校洗衣余额") {
            TextField("绑定手机号", text: $phone).keyboardType(.phonePad)
            if let value = StudentPhone.from(studentStore.info) {
                Button("使用个人信息中的手机号") { phone = value }
            }
            Button("查询洗衣余额", systemImage: "washer") { Task { await query(force: true) } }
                .disabled(model.loading || StudentPhone.normalized(phone) == nil)
            if model.loading { ProgressView("正在查询洗衣余额…") }
            ForEach(model.results.keys.sorted(), id: \.self) { key in LabeledContent(key, value: model.results[key] ?? "") }
            if let error = model.error { Text(error).font(.footnote).foregroundStyle(.secondary) }
            if let date = model.updatedAt { Text("更新于 \(date.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
            AppNavigationLink("慧新易校官方洗衣缴费") { HuiXinLaundryChargeView() }
        }
        .task(id: "\(appState.campus.rawValue)|\(StudentPhone.from(studentStore.info) ?? "")") {
            if StudentPhone.from(studentStore.info) == nil { await studentStore.refresh() }
            guard !Task.isCancelled else { return }
            phone = await studentStore.phoneForLifeServices() ?? phone
            await query(force: false)
        }
    }
    private func query(force: Bool) async { await model.refresh(campus: appState.campus, phone: phone, force: force) }
}
