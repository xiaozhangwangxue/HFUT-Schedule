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
    var body: some View {
        ContentUnavailableView(
            "暂无新通知",
            systemImage: "bell.slash",
            description: Text("考试提醒和校园通知将在授权后显示。")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background.ignoresSafeArea())
    }
}
