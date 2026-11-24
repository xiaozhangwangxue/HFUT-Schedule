import Combine
import SwiftUI

struct PlatformNavigationRoute: Identifiable, Hashable {
    let id: UUID
    let title: String
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

@MainActor
final class PlatformNavigationCoordinator: ObservableObject {
    static let shared = PlatformNavigationCoordinator()
    @Published private(set) var paths: [String: [PlatformNavigationRoute]] = [:]
    @Published private(set) var activeScope = "home"
    private var builders: [UUID: () -> AnyView] = [:]
    private var visibleLinks: Set<UUID> = []
    private var rootIDs: [String: UUID] = [:]
    private var rootTitles = ["home": "聚焦", "schedule": "课表", "services": "校园服务", "me": "选项"]
    private weak var appState: AppState?
    private var observations: Set<AnyCancellable> = []

    func attach(to state: AppState) {
        guard appState !== state else { return }
        observations.removeAll(); appState = state
        activate(Self.scope(for: state.selectedTab))
        state.$selectedTab.removeDuplicates().sink { [weak self] tab in
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
        let removed = Set((paths[scope] ?? []).map(\.id)).subtracting(path.map(\.id))
        paths[scope] = path
        for id in removed { releaseBuilderIfUnused(id) }
        if activeScope == scope { publishHistory() }
    }
    func activate(_ scope: String, title: String? = nil) {
        if let title { rootTitles[scope] = title }
        if rootIDs[scope] == nil { rootIDs[scope] = UUID() }
        activeScope = scope
        publishHistory()
    }
    func closeScope(_ scope: String, restoring parent: String?) {
        let removed = paths.removeValue(forKey: scope) ?? []
        for route in removed { releaseBuilderIfUnused(route.id) }
        if activeScope == scope { activate(parent ?? Self.scope(for: appState?.selectedTab ?? .home)) }
        rootIDs.removeValue(forKey: scope); rootTitles.removeValue(forKey: scope)
    }
    func deactivate(_ scope: String, restoring parent: String?) {
        if activeScope == scope { activate(parent ?? Self.scope(for: appState?.selectedTab ?? .home)) }
    }
    func register<Destination: View>(id: UUID, title: String?, @ViewBuilder destination: @escaping () -> Destination) -> PlatformNavigationRoute {
        let view = destination()
        let resolved = title ?? Self.title(for: view)
        builders[id] = { AnyView(view) }
        return PlatformNavigationRoute(id: id, title: resolved)
    }
    func linkAppeared(_ id: UUID) { visibleLinks.insert(id) }
    func linkDisappeared(_ id: UUID) { visibleLinks.remove(id); releaseBuilderIfUnused(id) }
    func destination(for route: PlatformNavigationRoute) -> AnyView {
        builders[route.id]?() ?? AnyView(ContentUnavailableView("页面已失效", systemImage: "arrow.uturn.backward", description: Text("请返回上一页重新打开。")))
    }
    func returnTo(_ id: UUID, in scope: String? = nil) {
        let targetScope = scope ?? activeScope
        if rootIDs[targetScope] == id { setPath([], scope: targetScope) }
        else if let index = paths[targetScope]?.firstIndex(where: { $0.id == id }) {
            setPath(Array((paths[targetScope] ?? []).prefix(index + 1)), scope: targetScope)
        }
        appState?.navigationReturnRequest = nil
    }
    private func releaseBuilderIfUnused(_ id: UUID) {
        guard !visibleLinks.contains(id), !paths.values.contains(where: { $0.contains(where: { $0.id == id }) }) else { return }
        builders.removeValue(forKey: id)
    }
    private func publishHistory() {
        appState?.navigationHistory = history(forScope: activeScope)
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
struct AppNavigationStack<Content: View>: View {
    @ObservedObject private var coordinator = PlatformNavigationCoordinator.shared
    @Environment(\.platformNavigationScope) private var parentScope
    @StateObject private var lifetime = PlatformNavigationLifetime()
    private let content: () -> Content
    private let title: String
    init(title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.content = content; self.title = title ?? PlatformNavigationCoordinator.title(for: String(describing: Content.self))
    }
    var body: some View {
        NavigationStack(path: coordinator.binding(forScope: lifetime.scope)) {
            content().navigationDestination(for: PlatformNavigationRoute.self) { coordinator.destination(for: $0) }
        }.environment(\.platformNavigationScope, lifetime.scope)
            .onAppear { lifetime.parent = parentScope; coordinator.activate(lifetime.scope, title: title) }
            .onDisappear { coordinator.deactivate(lifetime.scope, restoring: parentScope) }
    }
}

struct AppNavigationLink<Label: View, Destination: View>: View {
    @ObservedObject private var coordinator = PlatformNavigationCoordinator.shared
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
            .onAppear { coordinator.linkAppeared(id) }
            .onDisappear { coordinator.linkDisappeared(id) }
    }
}

extension AppNavigationLink where Label == Text {
    init(_ title: String, @ViewBuilder destination: @escaping () -> Destination) {
        self.init(title: title, destination: destination, label: { Text(title) })
    }
    init(_ title: String, destination: Destination) { self.init(title, destination: { destination }) }
}
