import SwiftUI

struct AcademicAdministrativeContactsView: View {
    @State private var contacts: [AcademicAdministrativeContact] = []
    @State private var total = 0
    @State private var page = 1
    @State private var query = ""
    @State private var sortByID = false
    @State private var loading = false
    @State private var showingLogin = false
    @State private var error: String?
    private var visible: [AcademicAdministrativeContact] {
        contacts.filter { query.isEmpty || "\($0.id) \($0.name)".localizedCaseInsensitiveContains(query) }.sorted { sortByID ? $0.id < $1.id : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var body: some View {
        List {
            if let error {
                Section { Text(error).foregroundStyle(.red); Button("登录指间工大") { showingLogin = true } }
            }
            Section("行政班通讯录（共 \(total) 人）") {
                ForEach(visible) { contact in
                    HStack(alignment: .top, spacing: 12) {
                        if let raw = contact.photoUrl, let url = URL(string: raw), ["https", "http"].contains(url.scheme ?? "") {
                            AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Image(systemName: "person.crop.square") }.frame(width: 44, height: 54).clipShape(RoundedRectangle(cornerRadius: 7))
                        } else { Image(systemName: "person.crop.square").font(.largeTitle).frame(width: 44) }
                        VStack(alignment: .leading, spacing: 5) {
                            Text(contact.name).font(.headline)
                            Text(contact.id).font(.caption.monospacedDigit()).foregroundStyle(.secondary).textSelection(.enabled)
                            if let phone = contact.phone, !phone.isEmpty { Text("电话 \(phone)").font(.caption).textSelection(.enabled) }
                            if let email = contact.email, !email.isEmpty { Text("邮件 \(email)").font(.caption).textSelection(.enabled) }
                        }
                    }.padding(.vertical, 4)
                }
            }
            AcademicPageControls(page: $page, loading: loading)
        }
        .navigationTitle("行政班同学")
        .searchable(text: $query, prompt: "姓名或学号")
        .toolbar { Button(sortByID ? "按学号" : "按姓名") { sortByID.toggle() } }
        .task(id: page) { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showingLogin, onDismiss: { Task { await load() } }) { AppNavigationStack { ZhiJianScannerLoginView() } }
        .overlay { if loading { ProgressView() } }
    }
    @MainActor private func load() async {
        loading = true; error = nil; defer { loading = false }
        do { let result = try await AcademicContactsClient.fetch(page: page); contacts = result.records; total = result.total }
        catch { AcademicServiceDiagnostics.record(context: "行政班通讯录读取", error: error); self.error = error.localizedDescription }
    }
}
