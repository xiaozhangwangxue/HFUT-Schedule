import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    var body: some View { RootTabShell(selection: appState.tabSelection) }
}

/// Tab selection invalidates the tab chrome, not every page that needs the
/// campus/account state from AppState.
private struct RootTabShell: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var selection: AppTabSelection
    private let navigation = PlatformNavigationCoordinator.shared
    @State private var showsLaunchpad = false
    @AppStorage("appShowsAllTabLabels") private var showsAllLabels = true
    @AppStorage("appBottomBarStyle") private var bottomBarStyle = "system"
    @AppStorage("appBottomBarInset") private var bottomInset = 8.0
    @AppStorage(AppSettingsKey.accentHex) private var accentHex = ""
    @AppStorage(AppSettingsKey.accentSaturation) private var saturation = 1.0
    @AppStorage(AppSettingsKey.colorStyle) private var colorStyle = "normal"
    private var themeRevision: String { "\(accentHex)|\(saturation)|\(colorStyle)" }
    private var usesCustomBar: Bool { bottomBarStyle == "floating" || !showsAllLabels }

    var body: some View {
        TabView(selection: $selection.selectedTab) {
            PersistentTabRoot(tab: .schedule, themeRevision: themeRevision, hidesSystemBar: usesCustomBar).equatable()
            .modifier(LaunchpadAccess(isPresented: $showsLaunchpad))
            .tabItem { Label("课程表", systemImage: "calendar") }
            .tag(AppTab.schedule)

            PersistentTabRoot(tab: .home, themeRevision: themeRevision, hidesSystemBar: usesCustomBar).equatable()
            .modifier(LaunchpadAccess(isPresented: $showsLaunchpad))
            .tabItem { Label("聚焦", systemImage: "lightbulb.fill") }
            .tag(AppTab.home)

            PersistentTabRoot(tab: .services, themeRevision: themeRevision, hidesSystemBar: usesCustomBar).equatable()
            .modifier(LaunchpadAccess(isPresented: $showsLaunchpad))
            .tabItem { Label("查询中心", systemImage: "square.grid.2x2.fill") }
            .tag(AppTab.services)

            PersistentTabRoot(tab: .me, themeRevision: themeRevision, hidesSystemBar: usesCustomBar).equatable()
            .modifier(LaunchpadAccess(isPresented: $showsLaunchpad))
            .tabItem { Label("选项", systemImage: "shippingbox.fill") }
            .tag(AppTab.me)
        }
        .toolbar(usesCustomBar ? .hidden : .visible, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if usesCustomBar {
                HStack(spacing: 2) {
                    tabButton(.schedule, title: "课程表", symbol: "calendar")
                    tabButton(.home, title: "聚焦", symbol: "lightbulb.fill")
                    tabButton(.services, title: "查询中心", symbol: "square.grid.2x2.fill")
                    tabButton(.me, title: "选项", symbol: "shippingbox.fill")
                }
                .padding(6)
                .adaptiveGlass(cornerRadius: bottomBarStyle == "floating" ? 26 : 12)
                .frame(maxWidth: 600)
                .padding(.horizontal, bottomBarStyle == "floating" ? 16 : 0)
                .padding(.bottom, min(24, max(0, bottomInset)))
            }
        }
        .onAppear { navigation.attach(to: appState); appState.consumePendingDestination() }
        .sheet(isPresented: $showsLaunchpad) { AppNavigationStack { PlatformLaunchpadView() } }
    }

    private func tabButton(_ tab: AppTab, title: String, symbol: String) -> some View {
        Button { selection.selectedTab = tab } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 19, weight: .medium))
                if showsAllLabels || selection.selectedTab == tab { Text(title).font(.caption2).lineLimit(1) }
            }
            .foregroundStyle(selection.selectedTab == tab ? AppTheme.accent : .secondary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(selection.selectedTab == tab ? AppTheme.accent.opacity(0.12) : .clear, in: Capsule())
            .contentShape(Capsule())
        }.buttonStyle(.plain).accessibilityLabel(title)
            .accessibilityAddTraits(selection.selectedTab == tab ? .isSelected : [])
    }
}

/// Keep the root screen's initializers and its AppStorage/StateObject wrappers
/// out of bottom-bar redraws. The child views continue observing their own
/// models and preferences; theme changes explicitly invalidate the shell.
private struct PersistentTabRoot: View, Equatable {
    let tab: AppTab
    let themeRevision: String
    let hidesSystemBar: Bool
    var body: some View {
        PlatformScopeNavigationStack(scope: PlatformNavigationCoordinator.scope(for: tab), hidesSystemBar: hidesSystemBar) {
            switch tab {
            case .schedule: ScheduleView()
            case .home: DashboardView()
            case .services: ServicesView()
            case .me: ProfileView()
            }
        }
    }
}

private struct LaunchpadAccess: ViewModifier {
    @Binding var isPresented: Bool
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("启动台", systemImage: "rectangle.stack") { isPresented = true }
            }
        }
    }
}

/// Uses the width proposed by its current window, so folding, rotation and
/// resizing recalculate columns without identifying a device or its screen.
struct CampusAdaptiveGrid<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let minimumItemWidth: CGFloat
    private let spacing: CGFloat
    private let maximumContentWidth: CGFloat
    private let content: Content

    init(minimumItemWidth: CGFloat = 160, spacing: CGFloat = 8,
         maximumContentWidth: CGFloat = 960, @ViewBuilder content: () -> Content) {
        self.minimumItemWidth = minimumItemWidth
        self.spacing = spacing
        self.maximumContentWidth = maximumContentWidth
        self.content = content()
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(
            .adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? max(260, minimumItemWidth) : minimumItemWidth),
            spacing: spacing,
            alignment: .top
        )], spacing: spacing) {
            content
        }
        .groupedGlass()
        .frame(maxWidth: maximumContentWidth)
    }
}
