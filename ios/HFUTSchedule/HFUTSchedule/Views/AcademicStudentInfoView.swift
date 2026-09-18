import SwiftUI

struct AcademicStudentInfoView: View {
    @EnvironmentObject private var studentStore: AcademicStudentStore

    var body: some View {
        Group {
            if let info = studentStore.info {
                List {
                    Section {
                        HStack(spacing: 14) {
                            GlassIcon(systemName: "person.crop.circle.fill", tint: AppTheme.violet, size: 56)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(info.name.isEmpty ? "在校生" : info.name)
                                    .font(.title3.bold())
                                Text(info.studentID)
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                    }

                    fieldSection("学籍信息", keys: ["院系", "院系名称", "学院", "专业", "专业名称", "专业方向", "行政班", "班级", "校区", "培养方案", "学籍状态", "学历层次", "学制", "入学日期", "预计毕业日期"])
                    fieldSection("基本信息", keys: ["性别", "政治面貌", "生源地"])
                    fieldSection("联系方式", keys: ["邮箱", "电话", "手机", "地址", "邮编"])

                    let remaining = remainingFields(info)
                    if !remaining.isEmpty {
                        Section("其他信息") {
                            ForEach(remaining, id: \.key) { item in
                                LabeledContent(item.key, value: item.value)
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            } else {
                ContentUnavailableView {
                    Label("尚未同步学籍信息", systemImage: "person.crop.circle.badge.questionmark")
                } description: {
                    Text("请先在“我的”中完成统一身份认证，登录成功后会自动读取并保存。")
                }
            }
        }
        .background(AppTheme.background.ignoresSafeArea())
    }

    @ViewBuilder
    private func fieldSection(_ title: String, keys: [String]) -> some View {
        if let info = studentStore.info {
            let rows = keys.compactMap { key -> (key: String, value: String)? in
                guard let value = info.fields[key], !value.isEmpty else { return nil }
                return (key, value)
            }
            if !rows.isEmpty {
                Section(title) {
                    ForEach(rows, id: \.key) { item in
                        LabeledContent(item.key, value: item.value)
                    }
                }
            }
        }
    }

    private func remainingFields(_ info: AcademicStudentInfo) -> [(key: String, value: String)] {
        let known = Set(["院系", "院系名称", "学院", "专业", "专业名称", "专业方向", "行政班", "班级", "校区", "培养方案", "学籍状态", "学历层次", "学制", "入学日期", "预计毕业日期", "性别", "政治面貌", "生源地", "邮箱", "电话", "手机", "地址", "邮编"])
        return info.fields
            .filter { !known.contains($0.key) && !$0.value.isEmpty }
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
    }
}
