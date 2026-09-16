import SwiftUI
import UIKit

struct CourseDetailView: View {
    let course: Course
    @AppStorage("academicConnectionMode") private var connectionMode = AcademicConnectionMode.direct.rawValue
    @State private var copiedCode = false

    private var details: CourseDetails { course.details ?? CourseDetails() }
    private var mode: AcademicConnectionMode { AcademicConnectionMode(rawValue: connectionMode) ?? .direct }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                summaryGrid
                dashedDivider
                teachers
                if !details.teachers.isEmpty { dashedDivider }
                academicGrid
                facts
                actionCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 34)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle(course.name)
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: CoursePortalPage.self) { page in
            PortalWebView(url: WebVPNURLConverter.convertedIfNeeded(page.url(mode: mode), mode: mode))
                .navigationTitle(page.title)
                .navigationBarTitleDisplayMode(.inline)
        }
        .alert("已复制课程代码", isPresented: $copiedCode) {
            Button("好", role: .cancel) {}
        }
    }

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
            detailCell("类型", value: details.type ?? "课程", icon: "star")
            detailCell("周数", value: details.weeksText ?? course.weekDescription ?? "未提供", icon: "calendar")
            if let count = details.classmatesCount {
                NavigationLink(value: CoursePortalPage.classmates) {
                    detailCell("同班同学", value: "\(count)人", icon: "person.2")
                }
                .buttonStyle(.plain)
            } else {
                detailCell("同班同学", value: "暂无数据", icon: "person.2")
            }
            detailCell("学分", value: details.credits.map(Self.creditText) ?? "未提供", icon: "rosette")
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var teachers: some View {
        if details.teachers.isEmpty {
            if !course.teacher.isEmpty {
                detailCell("教师", value: course.teacher, icon: "person")
            }
        } else {
            ForEach(Array(details.teachers.enumerated()), id: \.element.id) { index, teacher in
                HStack(spacing: 0) {
                    detailCell(
                        details.teachers.count == 1 ? "教师" : "教师 \(index + 1)",
                        value: teacher.name,
                        icon: "person"
                    )
                    if teacher.age != nil || teacher.title != nil || teacher.type != nil {
                        detailCell(
                            teacher.age.map { $0 < 100 ? "年龄 \($0)" : "年龄未知" } ?? "年龄未知",
                            value: [teacher.title, teacher.type].compactMap { $0 }.joined(separator: " ").nonEmpty ?? "信息暂无",
                            icon: "info.circle"
                        )
                    }
                }
            }
        }
    }

    private var academicGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
            if let department = details.department?.nonEmpty {
                detailCell("开设学院", value: department, icon: "function")
            }
            if let examMode = details.examMode?.nonEmpty {
                detailCell("考察方式", value: examMode, icon: "pencil.and.list.clipboard")
            }
        }
    }

    @ViewBuilder
    private var facts: some View {
        if let code = details.code?.nonEmpty {
            Button {
                UIPasteboard.general.string = code
                copiedCode = true
            } label: {
                wideDetailCell("课程代码--教学班", value: code, icon: "number")
            }
            .buttonStyle(.plain)
        }
        if let semester = details.semester?.nonEmpty {
            wideDetailCell("学期", value: semester, icon: "mappin.and.ellipse")
        }
        if let className = details.className?.nonEmpty {
            wideDetailCell("班级", value: className, icon: "door.left.hand.closed")
        }
        wideDetailCell(
            "上课安排",
            value: details.scheduleText?.nonEmpty ?? generatedScheduleText,
            icon: "clock"
        )
        if let remark = details.remark?.nonEmpty {
            wideDetailCell("备注", value: remark, icon: "info.circle")
        }
    }

    private var actionCard: some View {
        VStack(spacing: 0) {
            NavigationLink(value: CoursePortalPage.otherClasses) {
                actionRow("其他教学班开课查询", icon: "magnifyingglass")
            }
            Divider().padding(.leading, 54)
            NavigationLink(value: CoursePortalPage.classroom(course.location)) {
                actionRow("教室状态查询", subtitle: course.location.nonEmpty, icon: "door.left.hand.open")
            }
            Divider().padding(.leading, 54)
            NavigationLink(value: CoursePortalPage.failRate) {
                actionRow("挂科率查询", icon: "chart.pie")
            }
        }
        .padding(.vertical, 6)
        .adaptiveGlass(cornerRadius: 22, tint: AppTheme.accent.opacity(0.05), interactive: true)
        .padding(.top, 24)
    }

    private func detailCell(_ label: String, value: String, icon: String) -> some View {
        HStack(alignment: .center, spacing: 13) {
            Image(systemName: icon)
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.body).foregroundStyle(.primary).multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func wideDetailCell(_ label: String, value: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: icon)
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.body).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func actionRow(_ title: String, subtitle: String? = nil, icon: String) -> some View {
        HStack(spacing: 15) {
            Image(systemName: icon)
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body).foregroundStyle(.primary)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
    }

    private var dashedDivider: some View {
        Rectangle()
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 6]))
            .foregroundStyle(.secondary.opacity(0.38))
            .frame(height: 1)
            .padding(.vertical, 4)
    }

    private var generatedScheduleText: String {
        let weeks = details.weeksText ?? course.weekDescription ?? "本学期"
        let place = course.location.nonEmpty.map { " \($0)" } ?? ""
        let teacher = course.teacher.nonEmpty.map { " \($0)" } ?? ""
        return "\(weeks) \(course.weekdayName) \(course.startTime)~\(course.endTime)\(place)\(teacher)"
    }

    private static func creditText(_ value: Double) -> String {
        value.rounded() == value ? String(format: "%.1f", value) : String(value)
    }
}

private enum CoursePortalPage: Hashable {
    case classmates
    case otherClasses
    case classroom(String)
    case failRate

    var title: String {
        switch self {
        case .classmates: "同班同学"
        case .otherClasses: "其他教学班"
        case .classroom: "教室状态"
        case .failRate: "挂科率"
        }
    }

    func url(mode: AcademicConnectionMode) -> URL {
        switch self {
        case .otherClasses:
            AcademicPortal.url("for-std/lesson-search", mode: mode)
        case .classmates:
            URL(string: "https://jwglapp.hfut.edu.cn/")!
        case .classroom:
            URL(string: "https://jwglapp.hfut.edu.cn/")!
        case .failRate:
            URL(string: "https://community.hfut.edu.cn/")!
        }
    }
}

private extension String {
    var nonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
