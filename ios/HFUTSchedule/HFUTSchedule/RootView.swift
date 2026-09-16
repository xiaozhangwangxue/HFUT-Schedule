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
