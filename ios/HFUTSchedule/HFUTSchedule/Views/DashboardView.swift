import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var scheduleStore: ScheduleStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let columns = [GridItem(.adaptive(minimum: 102), spacing: 12)]

    private var todayIndex: Int {
        let weekday = Calendar.current.component(.weekday, from: Date())
        return ((weekday + 5) % 7) + 1
    }

    private var todayCourses: [Course] {
        scheduleStore.courses(on: todayIndex)
    }

    private var quickFeatures: [CampusFeature] {
        [1, 4, 6, 7, 19, 24].compactMap { id in
            FeatureCatalog.all.first { $0.id == id }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                hero

                VStack(spacing: 12) {
                    SectionHeader(title: "今天", subtitle: Course.weekdayNames[todayIndex - 1])
                    if todayCourses.isEmpty {
                        emptySchedule
                    } else {
                        ForEach(todayCourses.prefix(3)) { course in
                            CourseRow(course: course)
                        }
                    }
                }

                VStack(spacing: 12) {
                    SectionHeader(title: "常用服务", subtitle: "触手可及的校园入口")
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(quickFeatures) { feature in
                            NavigationLink(value: feature) {
                                QuickFeatureCard(feature: feature)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("聚在工大")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: CampusFeature.self) { feature in
            FeatureDetailView(feature: feature)
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [AppTheme.accent, AppTheme.violet, AppTheme.cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(.white.opacity(0.18))
                        .frame(width: 150)
                        .blur(radius: 2)
                        .offset(x: 38, y: -54)
                }

            VStack(alignment: .leading, spacing: 8) {
                Label(appState.campus.rawValue, systemImage: "location.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.86))
                Text(greeting)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                Text(todayCourses.isEmpty ? "把课程加入课表，今天的安排会在这里出现。" : "今天有 \(todayCourses.count) 节课，按自己的节奏出发。")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.86))
            }
            .padding(24)
        }
        .frame(height: 210)
        .shadow(color: AppTheme.accent.opacity(0.28), radius: 24, y: 14)
        .accessibilityElement(children: .combine)
        .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.92), value: todayCourses.count)
    }

    private var emptySchedule: some View {
        Button {
            appState.selectedTab = .schedule
        } label: {
            HStack(spacing: 14) {
                GlassIcon(systemName: "calendar.badge.plus")
                VStack(alignment: .leading, spacing: 3) {
                    Text("添加第一节课程")
                        .font(.headline)
                    Text("支持离线查看和导出到系统日历")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .contentShape(Rectangle())
            .adaptiveGlass(cornerRadius: 22, interactive: true)
        }
        .buttonStyle(.plain)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 0..<6: "夜深了"
        case 6..<11: "早上好"
        case 11..<14: "中午好"
        case 14..<18: "下午好"
        default: "晚上好"
        }
    }
}

private struct QuickFeatureCard: View {
    let feature: CampusFeature

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            GlassIcon(systemName: feature.systemImage, size: 42)
            Text(feature.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(feature.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(minHeight: 135, alignment: .topLeading)
        .adaptiveGlass(cornerRadius: 22, interactive: true)
    }
}

struct CourseRow: View {
    let course: Course

    private let colors: [Color] = [AppTheme.accent, AppTheme.violet, AppTheme.mint, .orange, .pink]

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 3)
                .fill(colors[abs(course.colorIndex) % colors.count])
                .frame(width: 5, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(course.name)
                    .font(.headline)
                Label(course.location.isEmpty ? "地点待定" : course.location, systemImage: "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(course.startTime)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                Text(course.endTime)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .adaptiveGlass(cornerRadius: 22)
        .accessibilityElement(children: .combine)
    }
}
