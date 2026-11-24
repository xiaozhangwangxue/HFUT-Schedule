import SwiftUI

struct PlatformDeepLinkView: View {
    let request: PlatformDeepLinkRequest
    var body: some View {
        Group {
            if request.target == "all_department" { CampusDepartmentDirectoryView() }
            else if request.target == "admission" { AdmissionsQueryView() }
            else if request.target == "all_exam" { PublicExamNoticesView() }
            else if request.target == "program_competition" { AcademicProgramProgressView() }
            else if let featureID = request.featureID, let feature = FeatureCatalog.all.first(where: { $0.id == featureID }) {
                FeatureDetailView(feature: feature)
            } else {
                switch request.target {
                case "settings_appearance": AppearanceSettingsView()
                case "settings_network": NetworkSettingsView()
                case "settings_backup", "settings_configurations": PreferencesSettingsView()
                case "settings_about_developer": DeveloperInfoView()
                case "settings_about": AboutView()
                case "version_info", "update_successfully": MaintenanceSettingsView()
                case "settings_deeplink": PlatformDeepLinkCatalogView()
                case "term_report": TermReportView()
                case "library_borrowed": LibraryServiceView(initialSection: 2)
                case "login": LoginPortalView()
                case "average_grade": PlatformGradeAnalysisView()
                case "all_program": AllAcademicProgramsView()
                case "add_event": CustomEventEditor(event: CustomEvent(title: "", start: Date(), end: Date().addingTimeInterval(3600)))
                case "news":
                    if let keyword = request.arguments["keyword"], !keyword.isEmpty { PlatformNewsSearchView(keyword: keyword) }
                    else { CampusNewsHubView() }
                case "teacher_search": TeacherSearchView(name: request.arguments["name"] ?? "")
                case "fail_rate": OfficialFailRateView(courseName: request.arguments["course_name"] ?? "", lessonCode: request.arguments["lesson_code"])
                case "course_classmates":
                    if let lessonID = request.lessonID { OfficialClassmatesView(lessonID: lessonID) }
                    else { ContentUnavailableView("深链参数无效", systemImage: "link.badge.plus", description: Text("lesson_id 必须是有效的正整数。")) }
                case "ai": AIAssistantView(initialQuestion: request.arguments["keyword"])
                case "agreement": PlatformAgreementView()
                default: ProfileView()
                }
            }
        }
    }
}

private struct PlatformGradeAnalysisView: View {
    @EnvironmentObject private var records: AcademicRecordsStore
    var body: some View { GradeAnalysisView(grades: records.gradeTerms.flatMap(\.grades)) }
}

struct PlatformDeepLinkCatalogView: View {
    @EnvironmentObject private var appState: AppState
    private let targets = (Array(PlatformDeepLinkRequest.featureIDs.keys) + Array(PlatformDeepLinkRequest.specialTargets)).sorted()
    @State private var pastedLink = ""
    @State private var invalidLink = false
    var body: some View {
        List {
            Section {
                Text("iOS 使用 hfut-schedule://。原版 hfut_schedule:// 链接可粘贴到此处，App 会先转换为 iOS 可解析的格式；参数保持不变。")
                TextField("粘贴原版或 iOS 深链", text: $pastedLink).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("打开粘贴的深链") { invalidLink = !appState.open(pastedLink) }
                if invalidLink { Text("链接格式无效，请检查 scheme 和查询参数。") .font(.footnote).foregroundStyle(.red) }
            }
            Section("带参数示例") {
                route("教师姓名", "teacher_search", [URLQueryItem(name: "name", value: "张")])
                route("新闻关键词", "news", [URLQueryItem(name: "keyword", value: "考试")])
                route("挂科率", "fail_rate", [URLQueryItem(name: "course_name", value: "高等数学")])
                route("AI 初始提问", "ai", [URLQueryItem(name: "keyword", value: "介绍一下合工大")])
                route("打开课表", "home", [URLQueryItem(name: "page", value: "CALENDAR")])
            }
            Section("页面入口") {
                ForEach(targets, id: \.self) { target in route(target, target, []) }
            }
        }.navigationTitle("深链")
    }
    private func route(_ title: String, _ host: String, _ query: [URLQueryItem]) -> some View {
        var parts = URLComponents(); parts.scheme = "hfut-schedule"; parts.host = host; parts.queryItems = query.isEmpty ? nil : query
        let url = parts.url!
        return VStack(alignment: .leading, spacing: 5) {
            Button(title) { appState.open(url) }
            Text(url.absoluteString).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Button("复制链接", systemImage: "doc.on.doc") { UIPasteboard.general.string = url.absoluteString }.font(.caption)
        }
    }
}

private struct PlatformAgreementView: View {
    var body: some View {
        List {
            Section("数据与账号") {
                Text("校方服务需要你有权使用的本人账号。登录 Cookie 与服务票据保存在设备的系统钥匙串中；导出的课表和系统日历会包含你选择的课程、考试及日程信息。")
                Text("AI 功能在发送前展示消息，使用你配置的服务处理内容。可在网络设置中删除密钥，在相关登录页退出账号。")
            }
            Section("开源许可") {
                Link("查看本项目与 Apache License 2.0", destination: URL(string: "https://github.com/xiaozhangwangxue/HFUT-Schedule")!)
            }
        }.navigationTitle("使用与隐私说明")
    }
}
