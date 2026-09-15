import SwiftUI
import AppIntents

@main
struct HFUTScheduleApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var scheduleStore = ScheduleStore()

    init() {
        HFUTAppShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(scheduleStore)
                .tint(AppTheme.accent)
        }
    }
}
