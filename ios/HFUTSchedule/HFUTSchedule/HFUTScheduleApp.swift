import SwiftUI

@main
struct HFUTScheduleApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var scheduleStore = ScheduleStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(scheduleStore)
                .tint(AppTheme.accent)
        }
    }
}
