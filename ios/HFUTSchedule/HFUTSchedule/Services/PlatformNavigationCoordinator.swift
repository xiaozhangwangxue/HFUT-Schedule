import Combine
import SwiftUI

@MainActor
final class PlatformNavigationDestination {
    let build: () -> AnyView
    init(build: @escaping () -> AnyView) { self.build = build }
}

struct PlatformNavigationRoute: Identifiable, Hashable {
    let id: UUID
    let title: String
    // The path and native NavigationLink own the lazy destination together.
    // Scrolling a source link offscreen cannot invalidate an active route.
    var destination: PlatformNavigationDestination? = nil
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

@MainActor
final class PlatformNavigationPath: ObservableObject {
    @Published fileprivate(set) var routes: [PlatformNavigationRoute] = []
}

@MainActor
final class PlatformNavigationCoordinator: ObservableObject {
    static let shared = PlatformNavigationCoordinator()
    @Published private(set) var paths: [String: [PlatformNavigationRoute]] = [:]
    @Published private(set) var activeScope = "home"
    private var pathStates: [String: PlatformNavigationPath] = [:]
    func pathState(for scope: String) -> PlatformNavigationPath {
        if let state = pathStates[scope] { return state }
        let state = PlatformNavigationPath(); state.routes = paths[scope] ?? []; pathStates[scope] = state
        return state
    }
    private var rootIDs: [String: UUID] = [:]
    private var rootTitles = ["home": "聚焦", "schedule": "课表", "services": "校园服务", "me": "选项"]
    private weak var appState: AppState?
    private var observations: Set<AnyCancellable> = []

    func attach(to state: AppState) {
        guard appState !== state else { return }
        observations.removeAll(); appState = state
        activate(Self.scope(for: state.selectedTab))
        state.tabSelection.$selectedTab.removeDuplicates().sink { [weak self] tab in
            Task { @MainActor in self?.activate(Self.scope(for: tab)) }
        }.store(in: &observations)
        state.$navigationReturnRequest.compactMap { $0 }.sink { [weak self] id in
            Task { @MainActor in self?.returnTo(id) }
        }.store(in: &observations)
    }

    static func scope(for tab: AppTab) -> String {
        switch tab { case .home: "home"; case .schedule: "schedule"; case .services: "services"; case .me: "me" }
    }
    func binding(for tab: AppTab) -> Binding<[PlatformNavigationRoute]> { binding(forScope: Self.scope(for: tab)) }
    func binding(forScope scope: String) -> Binding<[PlatformNavigationRoute]> {
        Binding(get: { self.paths[scope] ?? [] }, set: { self.setPath($0, scope: scope) })
    }
    func setPath(_ path: [PlatformNavigationRoute], scope: String) {
        guard paths[scope] != path else { return }
        paths[scope] = path
        pathStates[scope]?.routes = path
        if activeScope == scope { publishHistory() }
    }
    func activate(_ scope: String, title: String? = nil) {
        if let title { rootTitles[scope] = title }
        if rootIDs[scope] == nil { rootIDs[scope] = UUID() }
        if activeScope != scope { activeScope = scope }
        publishHistory()
    }
    func closeScope(_ scope: String, restoring parent: String?) {
        paths.removeValue(forKey: scope)
        if activeScope == scope { activate(parent ?? Self.scope(for: appState?.selectedTab ?? .home)) }
        rootIDs.removeValue(forKey: scope); rootTitles.removeValue(forKey: scope); pathStates.removeValue(forKey: scope)
    }
    func deactivate(_ scope: String, restoring parent: String?) {
        if activeScope == scope { activate(parent ?? Self.scope(for: appState?.selectedTab ?? .home)) }
    }
    func register<Destination: View>(id: UUID, title: String?, @ViewBuilder destination: @escaping () -> Destination) -> PlatformNavigationRoute {
        // Register closures, never destination values. A services grid can have
        // hundreds of links; rendering it must not initialise their models.
        let resolved = title ?? Self.title(for: String(describing: Destination.self))
        return PlatformNavigationRoute(id: id, title: resolved,
            destination: PlatformNavigationDestination { AnyView(destination()) })
    }
    func destination(for route: PlatformNavigationRoute) -> AnyView {
        route.destination?.build() ?? AnyView(ContentUnavailableView("页面已失效", systemImage: "arrow.uturn.backward", description: Text("请返回上一页重新打开。")))
    }
    func returnTo(_ id: UUID, in scope: String? = nil) {
        let targetScope = scope ?? activeScope
        if rootIDs[targetScope] == id { setPath([], scope: targetScope) }
        else if let index = paths[targetScope]?.firstIndex(where: { $0.id == id }) {
            setPath(Array((paths[targetScope] ?? []).prefix(index + 1)), scope: targetScope)
        }
        appState?.navigationReturnRequest = nil
    }
    private func publishHistory() {
        let history = history(forScope: activeScope)
        if appState?.navigationHistory != history { appState?.navigationHistory = history }
    }
    func history(forScope scope: String) -> [PlatformNavigationEntry] {
        if rootIDs[scope] == nil { rootIDs[scope] = UUID() }
        return [PlatformNavigationEntry(id: rootIDs[scope]!, title: rootTitles[scope] ?? "页面")]
            + (paths[scope] ?? []).map { PlatformNavigationEntry(id: $0.id, title: $0.title) }
    }
    static func title(for type: String) -> String {
        let names = ["PortalWebView": "网页", "TeacherSearchView": "教师查询", "OfficialClassmatesView": "同班同学",
            "OfficialFailRateView": "挂科率", "CourseDetailView": "课程详情", "UpcomingExamDetailView": "考试详情",
            "CustomEventEditor": "编辑日程", "CustomEventsView": "自建日程", "AppearanceSettingsView": "外观设置",
            "NetworkSettingsView": "网络设置", "PreferencesSettingsView": "偏好设置", "LibraryServiceView": "图书馆",
            "PlatformShortcutsView": "快捷入口", "PlatformDeepLinkCatalogView": "深链", "CalendarIntegrationView": "系统日历",
            "PlatformWidgetsSettingsView": "组件与实时活动", "PlatformDiagnosticsView": "错误详情", "AIAssistantView": "AI 助手",
            "AcademicRecordsView": "成绩与考试", "ProgramPlanView": "培养方案", "LoginPortalView": "安全登录",
            "DeveloperInfoView": "开发者选项", "TomorrowPlanView": "明天安排", "ElectricityServiceView": "宿舍电费"]
        return names[type] ?? "页面"
    }
    static func title<Destination: View>(for view: Destination) -> String {
        (view as? FeatureDetailView)?.feature.title ?? title(for: String(describing: Destination.self))
    }
}

private struct PlatformNavigationScopeKey: EnvironmentKey { static let defaultValue: String? = nil }
extension EnvironmentValues {
    var platformNavigationScope: String? {
        get { self[PlatformNavigationScopeKey.self] }
        set { self[PlatformNavigationScopeKey.self] = newValue }
    }
}

@MainActor
private final class PlatformNavigationLifetime: ObservableObject {
    let scope = "modal-" + UUID().uuidString
    var parent: String?
    deinit {
        let scope = scope, parent = parent
        Task { @MainActor in PlatformNavigationCoordinator.shared.closeScope(scope, restoring: parent) }
    }
}

/// Used for local sheet/editor stacks. Root uses the same coordinator with its
/// four tab bindings, so each navigation stack has a real independently owned path.
/// Each tab observes only its own path. Opening a services page does not
/// invalidate the timetable, Focus and settings trees at the same time.
struct PlatformScopeNavigationStack<Content: View>: View {
    private let coordinator = PlatformNavigationCoordinator.shared
    @ObservedObject private var path: PlatformNavigationPath
    private let scope: String
    private let hidesSystemBar: Bool
    private let content: Content
    init(scope: String, hidesSystemBar: Bool = false, @ViewBuilder content: () -> Content) {
        self.scope = scope; self.hidesSystemBar = hidesSystemBar; self.content = content()
        _path = ObservedObject(wrappedValue: PlatformNavigationCoordinator.shared.pathState(for: scope))
    }
    var body: some View {
        NavigationStack(path: coordinator.binding(forScope: scope)) {
            content
                .toolbar(hidesSystemBar ? .hidden : .visible, for: .tabBar)
                .navigationDestination(for: PlatformNavigationRoute.self) { route in
                    coordinator.destination(for: route).toolbar(hidesSystemBar ? .hidden : .visible, for: .tabBar)
                }
        }.environment(\.platformNavigationScope, scope)
    }
}

struct AppNavigationStack<Content: View>: View {
    private let coordinator = PlatformNavigationCoordinator.shared
    @Environment(\.platformNavigationScope) private var parentScope
    @StateObject private var lifetime = PlatformNavigationLifetime()
    private let content: () -> Content
    private let title: String
    init(title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.content = content; self.title = title ?? PlatformNavigationCoordinator.title(for: String(describing: Content.self))
    }
    var body: some View {
        PlatformScopeNavigationStack(scope: lifetime.scope, content: content)
            .onAppear { lifetime.parent = parentScope; coordinator.activate(lifetime.scope, title: title) }
            .onDisappear { coordinator.deactivate(lifetime.scope, restoring: parentScope) }
    }
}

struct AppNavigationLink<Label: View, Destination: View>: View {
    // Only stacks observe path changes. Links have no path-dependent UI.
    private let coordinator = PlatformNavigationCoordinator.shared
    @State private var id = UUID()
    private let title: String?
    private let destination: () -> Destination
    private let label: () -> Label
    init(title: String? = nil, @ViewBuilder destination: @escaping () -> Destination, @ViewBuilder label: @escaping () -> Label) {
        self.title = title; self.destination = destination; self.label = label
    }
    init(destination: Destination, @ViewBuilder label: @escaping () -> Label) {
        self.init(destination: { destination }, label: label)
    }
    var body: some View {
        let route = coordinator.register(id: id, title: title, destination: destination)
        SwiftUI.NavigationLink(value: route, label: label)

    }
}

extension AppNavigationLink where Label == Text {
    init(_ title: String, @ViewBuilder destination: @escaping () -> Destination) {
        self.init(title: title, destination: destination, label: { Text(title) })
    }
    init(_ title: String, destination: Destination) { self.init(title, destination: { destination }) }
}
