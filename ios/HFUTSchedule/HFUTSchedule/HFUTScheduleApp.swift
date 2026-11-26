import SwiftUI
import AppIntents

@main
struct HFUTScheduleApp: App {
    @UIApplicationDelegateAdaptor(PlatformApplicationDelegate.self) private var platformDelegate
    @StateObject private var appState = AppState()
    @StateObject private var scheduleStore = ScheduleStore()
    @StateObject private var customEventStore = CustomEventStore()
    @StateObject private var notificationManager = CourseNotificationManager()
    @StateObject private var academicRecordsStore = AcademicRecordsStore()
    @StateObject private var academicStudentStore = AcademicStudentStore()
    @AppStorage(AppSettingsKey.appearance) private var appearance = AppAppearance.auto.rawValue
    @AppStorage(AppSettingsKey.autoTermStart) private var autoTermStart = true
    @AppStorage(AppSettingsKey.manualTermStart) private var manualTermStart = 0.0
    @AppStorage(AppSettingsKey.defaultCourseSource) private var scheduleSource = "academic"
    @AppStorage("focusWidgetFontScale") private var focusWidgetFontScale = 1.0
    @AppStorage("focusWidgetSwitchesToTomorrow") private var focusWidgetTomorrow = true
    @AppStorage(AppSettingsKey.showFinishedToday) private var focusShowsFinished = true
    @AppStorage("courseLiveActivitiesEnabled") private var liveActivitiesEnabled = false
    @AppStorage(AppSettingsKey.accentHex) private var accentHex = ""
    @AppStorage(AppSettingsKey.accentSaturation) private var accentSaturation = 1.0
    @AppStorage(AppSettingsKey.colorStyle) private var colorStyle = "normal"
    @State private var themeAccent = AppTheme.accent
    @Environment(\.scenePhase) private var scenePhase

    init() {
        AppSettingsKey.migrateLegacyPreferences()
        CampusSessionStore.shared.bootstrap()
        AppTheme.restoreAccent()
        CourseNotificationDelegate.shared.install()
    }

    var body: some Scene {
        WindowGroup {
            // Scope shared stores around the presentation modifiers too, so
            // cold/warm deep links and shortcuts inherit the same objects.
            observedContent
                .environmentObject(appState)
                .environmentObject(scheduleStore)
                .environmentObject(customEventStore)
                .environmentObject(notificationManager)
                .environmentObject(academicRecordsStore)
                .environmentObject(academicStudentStore)
        }
    }

    private var baseContent: some View {
            RootView()
                .tint(themeAccent)
                .preferredColorScheme(preferredScheme)
    }

    private var routedContent: some View {
        baseContent
                .onOpenURL { appState.open($0) }
                .onReceive(NotificationCenter.default.publisher(for: .platformRouteRequested)) { notification in
                    if let url = notification.object as? URL { appState.open(url) }
                }
                .sheet(item: $appState.pendingOccurrence) { destination in
                    AppNavigationStack { PlatformOccurrenceDetailView(destination: destination) }
                }
                .sheet(item: $appState.pendingPlatformLink) { request in
                    AppNavigationStack { PlatformDeepLinkView(request: request) }
                }
                .sheet(item: $appState.pendingShortcut) { target in
                    AppNavigationStack { PlatformShortcutLandingView(target: target) }
                }
                .task { await prepareScene() }

    }

    private var observedContent: some View {
        routedContent
                .onChange(of: accentHex) { _, _ in restoreTheme() }
                .onChange(of: accentSaturation) { _, _ in restoreTheme() }
                .onChange(of: colorStyle) { _, _ in restoreTheme() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        scheduleStore.refreshWidgetSnapshot()
                        appState.consumePendingDestination()
                        startActivityUpdates()
                        Task { await rescheduleReminders() }
                    }
                    else {
                        CourseLiveActivityManager.shared.stopForegroundUpdates()
                        if phase == .background { WidgetRefreshCoordinator.shared.requestPendingReload() }
                    }
                }
                .onChange(of: manualTermStart) { _, _ in
                    scheduleStore.refreshWidgetSnapshot(forceNewRevision: true)
                    Task { await rescheduleReminders() }
                }
                .onChange(of: autoTermStart) { _, _ in
                    scheduleStore.refreshWidgetSnapshot(forceNewRevision: true)
                    Task { await rescheduleReminders() }
                }
                .onChange(of: scheduleSource) { _, value in
                    if value == "community", ScheduleSourceCoordinator.shared.friendID != nil { return }
                    ScheduleSourceCoordinator.shared.activate(ScheduleSource(rawValue: value) ?? .academic, store: scheduleStore)
                }
                .onChange(of: scheduleStore.courses) { _, _ in Task { await rescheduleReminders() } }
                .onChange(of: academicRecordsStore.exams) { _, _ in Task { await rescheduleReminders() } }
                .onChange(of: customEventStore.events) { _, _ in Task { await rescheduleReminders() } }
                .onChange(of: focusWidgetFontScale) { _, _ in Task { await rescheduleReminders() } }
                .onChange(of: focusWidgetTomorrow) { _, _ in Task { await rescheduleReminders() } }
                .onChange(of: focusShowsFinished) { _, _ in Task { await rescheduleReminders() } }
                .onChange(of: liveActivitiesEnabled) { _, value in
                    CourseLiveActivityManager.shared.isEnabled = value
                    Task { await rescheduleReminders() }
                }
                .onReceive(NotificationCenter.default.publisher(for: .campusCalendarChanged)) { _ in
                    Task { await rescheduleReminders() }
                }
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("appBackupRestored"))) { _ in
                    ScheduleSourceCoordinator.shared.reloadAfterBackup(store: scheduleStore)
                    Task { await rescheduleReminders() }
                }

    }

    @MainActor
    private func prepareScene() async {
        #if DEBUG
        if AppUIPreview.enabled {
            AppUIPreview.configure(state: appState, courses: scheduleStore, student: academicStudentStore)
            restoreTheme()
            if ProcessInfo.processInfo.arguments.contains("--navigation-performance-check") {
                await NavigationFrameProbe.run(state: appState)
            }
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--cas-preparation-check") {
            await CASPreparationProbe.run()
        } else if ProcessInfo.processInfo.arguments.contains("--navigation-performance-check") {
            await NavigationFrameProbe.run(state: appState)
        } else if ProcessInfo.processInfo.arguments.contains("--campus-function-check") {
            await CASPreparationProbe.runFunctions()
        } else if ProcessInfo.processInfo.arguments.contains("--campus-service-check") {
            await CASPreparationProbe.runServices()
        }
        #endif
        restoreTheme()
        let source = ScheduleSource(rawValue: scheduleSource) ?? .academic
        ScheduleSourceCoordinator.shared.activate(source, store: scheduleStore,
            friend: source == .community ? ScheduleSourceCoordinator.shared.friendID : nil)
        await rescheduleReminders()
        if scenePhase == .active { startActivityUpdates() }
        await CloudCommunityClient.shared.reportAnonymousUsageIfAllowed()
    }

    @MainActor
    private func startActivityUpdates() {
        CourseLiveActivityManager.shared.startForegroundUpdates {
            CourseLiveActivityInputs(courses: scheduleStore.courses, exams: academicRecordsStore.exams,
                events: customEventStore.events, termStart: ScheduleCalendar.termStart(from: scheduleStore.courses))
        }
    }

    private func restoreTheme() { AppTheme.restoreAccent(); themeAccent = AppTheme.accent }

    @MainActor
    private func rescheduleReminders() async {
        FocusWidgetPublisher.publish(schedule: scheduleStore, exams: academicRecordsStore.exams, events: customEventStore.events)
        try? await notificationManager.reschedule(for: scheduleStore.courses,
            exams: academicRecordsStore.exams, events: customEventStore.events,
            termStart: ScheduleCalendar.termStart(from: scheduleStore.courses))
        if scenePhase == .active {
            await CourseLiveActivityManager.shared.refresh(courses: scheduleStore.courses,
                exams: academicRecordsStore.exams, events: customEventStore.events)
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
