import SwiftUI
import AppIntents

@main
struct HFUTScheduleApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var scheduleStore = ScheduleStore()
    @StateObject private var notificationManager = CourseNotificationManager()
    @StateObject private var academicRecordsStore = AcademicRecordsStore()
    @StateObject private var academicStudentStore = AcademicStudentStore()
    @AppStorage(AppSettingsKey.appearance) private var appearance = AppAppearance.auto.rawValue

    init() {
        CampusSessionStore.shared.bootstrap()
        AppTheme.restoreAccent()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(scheduleStore)
                .environmentObject(notificationManager)
                .environmentObject(academicRecordsStore)
                .environmentObject(academicStudentStore)
                .tint(AppTheme.accent)
                .preferredColorScheme(preferredScheme)
                .onOpenURL { appState.open($0) }
        }
    }

    private var preferredScheme: ColorScheme? {
        switch AppAppearance(rawValue: appearance) ?? .auto {
        case .auto: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
