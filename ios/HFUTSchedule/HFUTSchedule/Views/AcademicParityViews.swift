import SwiftUI
import UIKit

struct CommunityGradesView: View {
    @State private var year = Calendar.current.component(.year, from: Date()) - (Calendar.current.component(.month, from: Date()) < 9 ? 1 : 0)
    @State private var term = Calendar.current.component(.month, from: Date()) >= 9 || Calendar.current.component(.month, from: Date()) <= 2 ? 1 : 2
    @State private var result: CommunityGradeResult?
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        List {
            Section("学期") {
                Stepper("\(year.formatted(.number.grouping(.never)))-\((year + 1).formatted(.number.grouping(.never)))", value: $year, in: 2000...2100)
                Picker("学期", selection: $term) { Text("第一学期").tag(1); Text("第二学期").tag(2) }
                Button("查询", systemImage: "magnifyingglass") { Task { await load() } }.disabled(loading)
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
            if let result {
                Section("智慧社区统计") {
                    LabeledContent("GPA", value: result.gpa.formatted())
                    LabeledContent("班级排名", value: result.classRanking)
                    LabeledContent("专业排名", value: result.majorRanking)
                }
                Section("课程成绩") {
                    ForEach(result.scoreInfoDTOList) { score in
                        VStack(alignment: .leading, spacing: 5) {
                            Label(score.courseName, systemImage: score.pass ? "checkmark.circle" : "exclamationmark.circle")
                            Text("分数 \(score.score.formatted()) · 学分 \(score.credit.formatted()) · 绩点 \(score.gpa.formatted())").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("智慧社区成绩")
        .overlay { if loading { ProgressView() } }
        .task { await load() }
        .refreshable { await load() }
    }
    @MainActor private func load() async {
        guard !loading else { return }; loading = true; error = nil
        defer { loading = false }
        do { result = try await OfficialCampusAPIClient.shared.fetchCommunityGrades(startYear: year, term: term) }
        catch { AcademicServiceDiagnostics.record(context: "学业平台服务", error: error); self.error = error.localizedDescription }
    }
}

struct PublicExamNoticesView: View {
    @State private var xuancheng = false
    @State private var page = 1
    @State private var items: [PublicExamNotice] = []
    @State private var error: String?
    @State private var loading = false
    var body: some View {
        List {
            Picker("校区", selection: $xuancheng) { Text("合肥").tag(false); Text("宣城").tag(true) }.pickerStyle(.segmented)
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(items) { item in
                AppNavigationLink { PortalWebView(url: item.url).navigationTitle(item.title) } label: {
                    VStack(alignment: .leading, spacing: 5) { Text(item.title); Text(item.date).font(.caption).foregroundStyle(.secondary) }
                }
            }
            HStack {
                Button("上一页") { page -= 1 }.disabled(page <= 1 || loading)
                Spacer(); Text("第 \(page) 页"); Spacer()
                Button("下一页") { page += 1 }.disabled(loading)
            }
            if items.isEmpty && !loading && error == nil { Text("该页没有匹配的考试通知。") }
        }
        .navigationTitle("公共考试通知")
        .task(id: "\(xuancheng)-\(page)") { await load() }
        .onChange(of: xuancheng) { _, _ in page = 1 }
        .refreshable { await load() }
        .overlay { if loading { ProgressView() } }
    }
    @MainActor private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do { items = try await PublicExamNoticeClient.fetch(xuancheng: xuancheng, page: page) }
        catch { AcademicServiceDiagnostics.record(context: "学业平台服务", error: error); self.error = error.localizedDescription }
    }
}

struct XiaoWuXingView: View {
    @State private var schools: [XiaoWuXingSchool] = []
    @State private var schoolCode: Int64 = -1
    @State private var username = ""
    @State private var password = ""
    @State private var functions: [XiaoWuXingFunction] = []
    @State private var image: UIImage?
    @State private var error: String?
    @State private var loading = false
    @State private var showLogin = false
    var body: some View {
        List {
            if showLogin || functions.isEmpty {
                Section("独立校务行账号") {
                    Picker("学校", selection: $schoolCode) {
                        Text("请选择学校").tag(Int64(-1))
                        ForEach(schools.filter { $0.schoolName.contains("合肥工业") || $0.schoolName.contains("宣城") }) { Text($0.schoolName).tag($0.schoolCode) }
                    }
                    TextField("学号", text: $username).textInputAutocapitalization(.never)
                    SecureField("校务行密码", text: $password)
                    Button("登录") { Task { await login() } }.disabled(loading || schoolCode < 0 || username.isEmpty || password.isEmpty)
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
            Section("可用证明与成绩单") {
                ForEach(functions) { function in
                    Button(function.printType) { Task { await preview(function) } }.disabled(loading)
                }
            }
            if let image {
                Section("文件预览") { Image(uiImage: image).resizable().scaledToFit().contextMenu { Button("保存到文件") { save(image) } } }
            }
        }
        .navigationTitle("校务行")
        .toolbar { Button("切换账号", systemImage: "person.crop.circle") { showLogin.toggle() } }
        .overlay { if loading { ProgressView() } }
        .task {
            do { schools = try await XiaoWuXingClient.shared.schools(); functions = try await XiaoWuXingClient.shared.functions() }
            catch { AcademicServiceDiagnostics.record(context: "学业平台服务", error: error); showLogin = true }
        }
    }
    @MainActor private func login() async {
        loading = true; error = nil; defer { loading = false }
        do {
            try await XiaoWuXingClient.shared.login(schoolCode: schoolCode, username: username, password: password)
            password = ""; functions = try await XiaoWuXingClient.shared.functions(); showLogin = false
        } catch { AcademicServiceDiagnostics.record(context: "学业平台服务", error: error); self.error = error.localizedDescription }
    }
    @MainActor private func preview(_ function: XiaoWuXingFunction) async {
        loading = true; error = nil; defer { loading = false }
        do {
            let data = try await XiaoWuXingClient.shared.preview(function)
            guard let value = UIImage(data: data) else { throw AcademicClientError.invalidData("预览图片无法解码") }
            image = value
        } catch { AcademicServiceDiagnostics.record(context: "学业平台服务", error: error); self.error = error.localizedDescription }
    }
    private func save(_ image: UIImage) {
        guard let data = image.pngData() else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("校务行-\(UUID().uuidString).png")
        do { try data.write(to: url); let controller = UIDocumentPickerViewController(forExporting: [url]);
            (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.keyWindow?.rootViewController?.present(controller, animated: true)
        } catch { AcademicServiceDiagnostics.record(context: "学业平台服务", error: error); self.error = error.localizedDescription }
    }
}
