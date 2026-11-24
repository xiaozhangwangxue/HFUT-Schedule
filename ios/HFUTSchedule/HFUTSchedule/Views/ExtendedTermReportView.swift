import SwiftUI
import Charts

struct CampusReportMetric: Identifiable { let name: String; let value: String; var id: String { name } }
struct CampusReportPoint: Identifiable { let label: String; let value: Double; var id: String { label } }
struct CampusReportSection: Identifiable {
    let id: String
    let title: String
    var metrics: [CampusReportMetric] = []
    var points: [CampusReportPoint] = []
    var note = ""
}

struct CampusReportCard: View {
    let section: CampusReportSection
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(section.title).font(.title2.bold())
            ForEach(section.metrics) { LabeledContent($0.name, value: $0.value).font(.subheadline) }
            if !section.points.isEmpty {
                Chart(section.points) { point in
                    BarMark(x: .value("数值", point.value), y: .value("项目", point.label))
                        .foregroundStyle(AppTheme.accent)
                }.frame(height: CGFloat(min(12, section.points.count)) * 28 + 30)
            }
            if !section.note.isEmpty { Text(section.note).font(.caption).foregroundStyle(.secondary) }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }
}

struct ExtendedTermReportView: View {
    @EnvironmentObject private var schedule: ScheduleStore
    @EnvironmentObject private var records: AcademicRecordsStore
    @EnvironmentObject private var student: AcademicStudentStore
    @EnvironmentObject private var appState: AppState
    @State private var start = Date().addingTimeInterval(-120 * 86400)
    @State private var end = Date()
    @State private var selectedTerm = "全部"
    @State private var selected: Set<String> = ["study","grades","expenses","life","network"]
    @State private var bills: [CampusCardBill]?
    @State private var borrowed: [LibraryBorrowRecord]?
    @State private var network: [SchoolNetworkMonthRecord]?
    @State private var dormitory: [OfficialDormitoryScore]?
    @State private var ranks: CommunityGradeResult?
    @State private var errors: [String: String] = [:]
    @State private var busy = false
    @State private var shareURLs: [URL] = []
    @State private var showsShare = false
    @State private var exportError: String?
    private let options = [("study","课程与考试"),("grades","成绩与排名"),("expenses","消费与预测"),("life","图书馆与宿舍"),("network","校园网")]
    private var grades: [AcademicGrade] { records.gradeTerms.filter { selectedTerm == "全部" || $0.term == selectedTerm }.flatMap(\.grades) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GroupBox("报告准备") {
                    VStack(spacing: 12) {
                        DatePicker("开始", selection: $start, in: ...end, displayedComponents: .date)
                        DatePicker("结束", selection: $end, in: start..., displayedComponents: .date)
                        Picker("成绩学期", selection: $selectedTerm) {
                            Text("全部").tag("全部")
                            ForEach(records.gradeTerms) { Text($0.term).tag($0.term) }
                        }
                        ForEach(options, id: \.0) { id, title in
                            Toggle(title, isOn: Binding(get: { selected.contains(id) }, set: { if $0 { selected.insert(id) } else { selected.remove(id) } }))
                        }
                        HStack {
                            Button("全选") { selected = Set(options.map(\.0)) }
                            Button("生成报告") { Task { await load() } }.disabled(busy || selected.isEmpty)
                        }
                    }.font(.subheadline)
                }.disabled(busy)
                if busy { ProgressView("正在读取报告数据…") }
                ForEach(sections) { CampusReportCard(section: $0) }
                Text("报告使用已同步的学业数据和本次查询的校园服务数据。查询失败的项目会单独注明，不会将缺失数据写成零。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(16).frame(maxWidth: 800).frame(maxWidth: .infinity)
        }
        .background(AppTheme.background)
        .navigationTitle("学期报告")
        .toolbar { Button("导出图片", systemImage: "square.and.arrow.up") { export() }.disabled(busy || sections.isEmpty) }
        .sheet(isPresented: $showsShare) { CampusReportShareSheet(urls: shareURLs) }
        .alert("报告导出失败", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("好", role: .cancel) { exportError = nil }
        } message: { Text(exportError ?? "") }
        .onAppear { if let date = ScheduleCalendar.termStart(from: schedule.courses) { start = date } }
        .onChange(of:start) { _, _ in clearRemoteData() }
        .onChange(of:end) { _, _ in clearRemoteData() }
        .onChange(of:selectedTerm) { _, _ in ranks = nil }
    }

    private var sections: [CampusReportSection] {
        var result: [CampusReportSection] = []
        let label = "\(HolidayCalendarStore.key(for: start)) 至 \(HolidayCalendarStore.key(for: end))"
        if selected.contains("study") {
            let occurrences = PlatformScheduleResolver.occurrences(courses: schedule.courses, exams: records.exams,
                termStart: ScheduleCalendar.termStart(from: schedule.courses)).filter { $0.start >= Calendar.current.startOfDay(for: start) && $0.start < endOfRange }
            let lessons = occurrences.filter { $0.kind == .course }, exams = occurrences.filter { $0.kind == .exam }
            let hours = lessons.reduce(0) { $0 + max(0, $1.end.timeIntervalSince($1.start) / 3600) }
            let places = Dictionary(grouping: lessons.filter { !$0.location.isEmpty }, by: \.location).mapValues(\.count)
            result.append(CampusReportSection(id: "study", title: "课程与考试", metrics: [
                .init(name:"课程",value:"\(Set(lessons.map(\.title)).count) 门"), .init(name:"课程时段",value:"\(lessons.count) 次"),
                .init(name:"课堂时长",value:String(format:"%.1f 小时",hours)), .init(name:"考试",value:"\(exams.count) 场")],
                points: places.sorted { $0.value > $1.value }.prefix(12).map { .init(label:$0.key,value:Double($0.value)) }, note: label))
        }
        if selected.contains("grades") {
            let numeric = grades.compactMap { Double($0.score) }
            var metrics: [CampusReportMetric] = [.init(name:"统计课程",value:"\(grades.count) 门"),
                .init(name:"平均成绩",value:GradeStatistics.weightedScore(grades).map { String(format:"%.2f",$0) } ?? "暂无可计算成绩"),
                .init(name:"平均绩点",value:GradeStatistics.weightedGPA(grades).map { String(format:"%.3f",$0) } ?? "暂无可计算绩点"),
                .init(name:"不及格",value:"\(numeric.filter { $0 < 60 }.count) 门")]
            if let ranks { metrics += [.init(name:"社区班级排名",value:ranks.classRanking),.init(name:"社区专业排名",value:ranks.majorRanking)] }
            result.append(CampusReportSection(id:"grades",title:"成绩与排名",metrics:metrics,
                points: Array(records.gradeTerms.compactMap { term in GradeStatistics.weightedScore(term.grades).map { CampusReportPoint(label:term.term,value:$0) } }.suffix(12)),
                note: errors["grades"] ?? "成绩趋势基于本机已同步的各学期；排名以选定学期的社区返回值为准。"))
        }
        if selected.contains("expenses") {
            var section = CampusReportSection(id:"expenses",title:"消费与预测",note:errors["expenses"] ?? "点击生成报告读取指定日期的账单。")
            if let bills {
                let value = CampusCardAnalysis.forecast(bills)
                section.metrics = [.init(name:"消费记录",value:"\(bills.filter { $0.turnoverType == "消费" }.count) 条"),
                    .init(name:"日均消费",value:String(format:"¥ %.2f",value.dailyAverage)),
                    .init(name:"月均消费",value:String(format:"¥ %.2f",value.monthlyAverage)),
                    .init(name:"次日预测",value:value.nextDay.map { String(format:"¥ %.2f",$0) } ?? "样本不足"),
                    .init(name:"下月预测",value:value.nextMonth.map { String(format:"¥ %.2f",$0) } ?? "样本不足")]
                section.points = value.merchants.sorted { $0.value > $1.value }.prefix(12).map { .init(label:$0.key,value:$0.value) }
                section.note = label + "。预测沿用原版异常值过滤和线性拟合，仅基于已取得账单。"
            }
            result.append(section)
        }
        if selected.contains("life") {
            var section = CampusReportSection(id:"life",title:"图书馆与宿舍",note:errors["life"] ?? "点击生成报告读取生活数据。")
            if let borrowed {
                section.metrics += [.init(name:"借阅记录",value:"\(borrowed.count) 条"), .init(name:"逾期待还",value:"\(borrowed.filter { $0.status == "02" }.count) 本")]
                section.points = LibraryKeywordAnalysis.frequencies(borrowed.map { $0.libraryDetail.detail.keywords }).prefix(12).map { .init(label:$0.word,value:Double($0.count)) }
            }
            if let dormitory { section.metrics += dormitory.map { .init(name:$0.title,value:$0.value) } }
            result.append(section)
        }
        if selected.contains("network") {
            var section = CampusReportSection(id:"network",title:"校园网",note:errors["network"] ?? "点击生成报告读取网络月账单。")
            if let network {
                section.metrics = [.init(name:"总费用",value:String(format:"¥ %.2f",network.reduce(0) { $0 + $1.baseFee + $1.usageFee })),
                    .init(name:"总流量",value:String(format:"%.2f GB",network.reduce(0) { $0 + $1.flowMB } / 1024)),
                    .init(name:"使用时长",value:String(format:"%.1f 小时",Double(network.reduce(0) { $0 + $1.durationMinutes }) / 60))]
                section.points = network.suffix(12).map { .init(label:$0.startDate,value:$0.flowMB / 1024) }; section.note = label
            }
            result.append(section)
        }
        return result
    }
    private var endOfRange: Date { Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: end)) ?? end }
    private func clearRemoteData() { bills = nil; borrowed = nil; network = nil; dormitory = nil; errors = [:] }
    @MainActor private func load() async {
        guard !busy else { return }; busy = true; errors = [:]
        defer { busy = false }
        if selected.contains("expenses") {
            do {
                let all = try await CampusServiceClient.shared.fetchAllCampusCardBills()
                let first = HolidayCalendarStore.key(for:start), last = HolidayCalendarStore.key(for:end)
                bills = all.filter { $0.day >= first && $0.day <= last }
            } catch { bills = nil; errors["expenses"] = error.localizedDescription }
        }
        if selected.contains("life") {
            do {
                let all = try await CampusServiceClient.shared.fetchLibraryBorrowRecords(pageSize:500)
                let first = HolidayCalendarStore.key(for:start), last = HolidayCalendarStore.key(for:end)
                borrowed = all.filter { let day = String($0.createdTime.prefix(10)).replacingOccurrences(of:"/",with:"-"); return day >= first && day <= last }
            } catch { borrowed = nil; errors["life"] = error.localizedDescription }
            do { dormitory = try await OfficialCampusAPIClient.shared.fetchDormitory().2 }
            catch { dormitory = nil; errors["life"] = (errors["life"].map { $0 + "\n" } ?? "") + error.localizedDescription }
        }
        if selected.contains("network") {
            do { network = try await SchoolNetworkClient.shared.history(from:start,to:end,xuancheng:appState.campus == .xuancheng) }
            catch { network = nil; errors["network"] = error.localizedDescription }
        }
        if selected.contains("grades"), selectedTerm != "全部", let year = Int(selectedTerm.prefix(4)) {
            do { ranks = try await OfficialCampusAPIClient.shared.fetchCommunityGrades(startYear:year,term:selectedTerm.contains("第二") || selectedTerm.hasSuffix("-2") ? 2 : 1) }
            catch { ranks = nil; errors["grades"] = error.localizedDescription }
        }
    }
    @MainActor private func export() {
        do {
            shareURLs = try CampusReportExporter.export(sections: sections, start: start, end: end)
            showsShare = !shareURLs.isEmpty
        } catch { exportError = error.localizedDescription }
    }

}

enum CampusReportExportError: LocalizedError {
    case rendering
    var errorDescription: String? { "无法生成报告图片，请稍后重试。" }
}

@MainActor
enum CampusReportExporter {
    static func export(sections: [CampusReportSection], start: Date, end: Date,
                       directory: URL = FileManager.default.temporaryDirectory) throws -> [URL] {
        var urls: [URL] = []
        do {
            for section in sections {
                let renderer = ImageRenderer(content: VStack(alignment: .leading, spacing: 16) {
                    Text("聚在工大 · 学期报告").font(.largeTitle.bold())
                    Text("\(HolidayCalendarStore.key(for: start)) 至 \(HolidayCalendarStore.key(for: end))").font(.subheadline)
                    CampusReportCard(section: section)
                }.padding(28).frame(width: 700).background(Color.white).environment(\.colorScheme, .light))
                renderer.scale = 2
                guard let image = renderer.uiImage, let data = image.pngData() else { throw CampusReportExportError.rendering }
                let url = directory.appendingPathComponent("HFUT-report-\(section.id)-\(UUID().uuidString).png")
                try data.write(to: url, options: .atomic)
                urls.append(url)
            }
            return urls
        } catch {
            for url in urls { try? FileManager.default.removeItem(at: url) }
            throw error
        }
    }
}

private struct CampusReportShareSheet: UIViewControllerRepresentable {
    let urls: [URL]
    func makeUIViewController(context:Context) -> UIActivityViewController { UIActivityViewController(activityItems:urls,applicationActivities:nil) }
    func updateUIViewController(_ controller:UIActivityViewController,context:Context) { }
}
