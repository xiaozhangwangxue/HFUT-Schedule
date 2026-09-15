import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            NavigationStack {
                DashboardView()
            }
            .tabItem { Label("首页", systemImage: "house.fill") }
            .tag(AppTab.home)

            NavigationStack {
                ScheduleView()
            }
            .tabItem { Label("课表", systemImage: "calendar") }
            .tag(AppTab.schedule)

            NavigationStack {
                ServicesView()
            }
            .tabItem { Label("服务", systemImage: "square.grid.2x2.fill") }
            .tag(AppTab.services)

            NavigationStack {
                ProfileView()
            }
            .tabItem { Label("我的", systemImage: "person.crop.circle.fill") }
            .tag(AppTab.me)
        }
    }
}
