import SwiftUI
import AppIntents

@main
struct HFUTScheduleApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var scheduleStore = ScheduleStore()
    @StateObject private var notificationManager = CourseNotificationManager()
    @StateObject private var academicRecordsStore = AcademicRecordsStore()
    @StateObject private var academicStudentStore = AcademicStudentStore()

    init() {
        CampusSessionStore.shared.bootstrap()
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
                .onOpenURL { appState.open($0) }
        }
    }
}
