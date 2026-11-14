import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            NavigationStack {
                ScheduleView()
            }
            .tabItem { Label("课程表", systemImage: "calendar") }
            .tag(AppTab.schedule)

            NavigationStack {
                DashboardView()
            }
            .tabItem { Label("聚焦", systemImage: "lightbulb.fill") }
            .tag(AppTab.home)

            NavigationStack {
                ServicesView()
            }
            .tabItem { Label("查询中心", systemImage: "square.grid.2x2.fill") }
            .tag(AppTab.services)

            NavigationStack {
                ProfileView()
            }
            .tabItem { Label("选项", systemImage: "shippingbox.fill") }
            .tag(AppTab.me)
        }
        .onAppear { appState.consumePendingDestination() }
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
