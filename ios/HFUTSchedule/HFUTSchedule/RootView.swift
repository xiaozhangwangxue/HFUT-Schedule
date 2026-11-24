import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var navigation = PlatformNavigationCoordinator.shared
    @State private var showsLaunchpad = false
    @AppStorage("appShowsAllTabLabels") private var showsAllLabels = true
    @AppStorage("appBottomBarStyle") private var bottomBarStyle = "system"
    @AppStorage("appBottomBarInset") private var bottomInset = 8.0
    private var usesCustomBar: Bool { bottomBarStyle == "floating" || !showsAllLabels }

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            NavigationStack(path: navigation.binding(for: .schedule)) {
                ScheduleView()
                    .navigationDestination(for: PlatformNavigationRoute.self) { navigation.destination(for: $0) }
            }
            .environment(\.platformNavigationScope, "schedule")
            .modifier(LaunchpadAccess(isPresented: $showsLaunchpad))
            .tabItem { Label("课程表", systemImage: "calendar") }
            .tag(AppTab.schedule)

            NavigationStack(path: navigation.binding(for: .home)) {
                DashboardView()
                    .navigationDestination(for: PlatformNavigationRoute.self) { navigation.destination(for: $0) }
            }
            .environment(\.platformNavigationScope, "home")
            .modifier(LaunchpadAccess(isPresented: $showsLaunchpad))
            .tabItem { Label("聚焦", systemImage: "lightbulb.fill") }
            .tag(AppTab.home)

            NavigationStack(path: navigation.binding(for: .services)) {
                ServicesView()
                    .navigationDestination(for: PlatformNavigationRoute.self) { navigation.destination(for: $0) }
            }
            .environment(\.platformNavigationScope, "services")
            .modifier(LaunchpadAccess(isPresented: $showsLaunchpad))
            .tabItem { Label("查询中心", systemImage: "square.grid.2x2.fill") }
            .tag(AppTab.services)

            NavigationStack(path: navigation.binding(for: .me)) {
                ProfileView()
                    .navigationDestination(for: PlatformNavigationRoute.self) { navigation.destination(for: $0) }
            }
            .environment(\.platformNavigationScope, "me")
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
        Button { appState.selectedTab = tab } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 19, weight: .medium))
                if showsAllLabels || appState.selectedTab == tab { Text(title).font(.caption2).lineLimit(1) }
            }
            .foregroundStyle(appState.selectedTab == tab ? AppTheme.accent : .secondary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(appState.selectedTab == tab ? AppTheme.accent.opacity(0.12) : .clear, in: Capsule())
            .contentShape(Capsule())
        }.buttonStyle(.plain).accessibilityLabel(title)
            .accessibilityAddTraits(appState.selectedTab == tab ? .isSelected : [])
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
            spacing: spacing
        )], spacing: spacing) {
            content
        }
        .frame(maxWidth: maximumContentWidth)
    }
}
