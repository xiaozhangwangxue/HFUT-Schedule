import SwiftUI

struct FeatureDetailView: View {
    let feature: CampusFeature

    var body: some View {
        Group {
            switch feature.nativeDestination {
            case .scanner:
                ScannerView()
            case .schedule:
                ScheduleView()
            case .calendar:
                portalOrUnavailable
            case .notifications:
                NotificationsView()
            case .settings:
                ProfileView()
            case .grades:
                AcademicRecordsView(kind: .grades)
            case .exams:
                AcademicRecordsView(kind: .exams)
            case .personInfo:
                AcademicStudentInfoView()
            case nil:
                portalOrUnavailable
            }
        }
        .navigationTitle(feature.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var portalOrUnavailable: some View {
        if let url = feature.url {
            if ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                PortalWebView(url: url)
            } else {
                ExternalLinkView(feature: feature, url: url)
            }
        } else {
            ContentUnavailableView(
                feature.title,
                systemImage: feature.systemImage,
                description: Text("此原生模块正在从 Android 迁移到 SwiftUI。")
            )
        }
    }
}

private struct ExternalLinkView: View {
    let feature: CampusFeature
    let url: URL
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 22) {
            GlassIcon(systemName: feature.systemImage, size: 72)
            Text(feature.subtitle)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Button("打开对应应用", systemImage: "arrow.up.forward.app") {
                openURL(url)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background.ignoresSafeArea())
    }
}

private struct NotificationsView: View {
    @EnvironmentObject private var scheduleStore: ScheduleStore
    @EnvironmentObject private var notificationManager: CourseNotificationManager
    @State private var message: String?

    var body: some View {
        VStack(spacing: 20) {
            GlassIcon(systemName: "bell.badge.fill", tint: .orange, size: 72)
            Text("课程提醒")
                .font(.title2.bold())
            Text("通知权限：\(notificationManager.authorizationDescription)\n已安排 \(notificationManager.pendingReminderCount) 条每周提醒")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if notificationManager.authorizationStatus == .denied {
                Text("请前往“设置 → 通知 → 聚在工大”开启通知。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Button("授权并刷新提醒", systemImage: "bell.and.waves.left.and.right") {
                    Task { await updateReminders() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background.ignoresSafeArea())
        .task { await notificationManager.refresh() }
        .alert("课程提醒", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("好") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private func updateReminders() async {
        do {
            notificationManager.isEnabled = true
            try await notificationManager.reschedule(for: scheduleStore.courses)
            message = "课程提醒已更新。"
        } catch {
            message = error.localizedDescription
        }
    }
}
