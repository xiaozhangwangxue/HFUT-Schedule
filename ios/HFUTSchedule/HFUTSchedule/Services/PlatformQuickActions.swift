import AppIntents
import SwiftUI
import UIKit

enum CampusShortcutTarget: String, AppEnum, CaseIterable, Identifiable, Codable {
    case schedule, services, hefeiNetwork, xuanchengNetwork, recharge, campusCard, scanner, hotWater, expressPDD, expressTaobao, payCode, library
    var id: String { rawValue }
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "校园快捷入口"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .schedule: "课表", .services: "校园服务", .hefeiNetwork: "合肥校园网登录", .xuanchengNetwork: "宣城校园网登录",
        .recharge: "校园卡充值", .campusCard: "校园卡", .scanner: "扫码", .hotWater: "饮水热水",
        .expressPDD: "拼多多取件码", .expressTaobao: "淘宝取件码", .payCode: "付款码", .library: "图书馆"
    ]
    var title: String {
        switch self {
        case .schedule: "课表"; case .services: "校园服务"; case .hefeiNetwork: "合肥校园网登录"
        case .xuanchengNetwork: "宣城校园网登录"; case .recharge: "校园卡充值"; case .campusCard: "校园卡"
        case .scanner: "扫码"; case .hotWater: "饮水热水"; case .expressPDD: "拼多多取件码"
        case .expressTaobao: "淘宝取件码"; case .payCode: "付款码"; case .library: "图书馆"
        }
    }
    var symbol: String {
        switch self {
        case .schedule: "calendar"; case .services: "square.grid.2x2"; case .hefeiNetwork, .xuanchengNetwork: "wifi"
        case .recharge: "yensign.circle"; case .campusCard: "creditcard"; case .scanner: "qrcode.viewfinder"
        case .hotWater: "drop"; case .expressPDD, .expressTaobao: "shippingbox"; case .payCode: "barcode"; case .library: "books.vertical"
        }
    }
    var url: URL {
        var parts = URLComponents(); parts.scheme = "hfut-schedule"; parts.host = "shortcut"
        parts.queryItems = [URLQueryItem(name: "target", value: rawValue)]
        return parts.url!
    }
    func enqueue() {
        UserDefaults.standard.set(url.absoluteString, forKey: "pendingPlatformURL")
        Task { @MainActor in NotificationCenter.default.post(name: .platformRouteRequested, object: url) }
    }
}

@MainActor
enum HomeScreenShortcutStore {
    static let storageKey = "homeScreenShortcutTargets.v1"
    static func selected(defaults: UserDefaults = .standard) -> [CampusShortcutTarget] {
        guard let saved = defaults.stringArray(forKey: storageKey) else { return [.scanner, .campusCard, .payCode, .schedule] }
        var seen = Set<CampusShortcutTarget>()
        return saved.compactMap(CampusShortcutTarget.init(rawValue:)).filter { seen.insert($0).inserted }.prefix(4).map { $0 }
    }
    static func save(_ values: [CampusShortcutTarget], defaults: UserDefaults = .standard) {
        var seen = Set<CampusShortcutTarget>()
        let values = values.filter { seen.insert($0).inserted }.prefix(4)
        defaults.set(values.map(\.rawValue), forKey: storageKey)
        refresh(defaults: defaults)
    }
    static func refresh(defaults: UserDefaults = .standard) {
        UIApplication.shared.shortcutItems = selected(defaults: defaults).map {
            UIApplicationShortcutItem(type: "hfut." + $0.rawValue, localizedTitle: $0.title,
                localizedSubtitle: nil, icon: UIApplicationShortcutIcon(systemImageName: $0.symbol), userInfo: nil)
        }
    }
    @discardableResult static func handle(_ item: UIApplicationShortcutItem) -> Bool {
        guard item.type.hasPrefix("hfut."), let target = CampusShortcutTarget(rawValue: String(item.type.dropFirst(5))) else { return false }
        target.enqueue()
        return true
    }
}

/// Install with UIApplicationDelegateAdaptor. The scene callbacks cover both a
/// cold launch and an already running SwiftUI app's Home Screen quick action.
final class PlatformApplicationDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        CourseNotificationDelegate.shared.install()
        HomeScreenShortcutStore.refresh()
        if let item = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem { _ = HomeScreenShortcutStore.handle(item) }
        return true
    }
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let shortcut = options.shortcutItem { _ = HomeScreenShortcutStore.handle(shortcut) }
        let configuration = (connectingSceneSession.configuration.copy() as? UISceneConfiguration)
            ?? UISceneConfiguration(name: connectingSceneSession.configuration.name, sessionRole: connectingSceneSession.role)
        if connectingSceneSession.role == .windowApplication { configuration.delegateClass = PlatformShortcutSceneDelegate.self }
        return configuration
    }
    func application(_ application: UIApplication, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) { completionHandler(HomeScreenShortcutStore.handle(shortcutItem)) }
}

final class PlatformShortcutSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) { completionHandler(HomeScreenShortcutStore.handle(shortcutItem)) }
}

struct OpenCampusTargetIntent: AppIntent {
    static var title: LocalizedStringResource = "打开校园快捷入口"
    static var openAppWhenRun = true
    @Parameter(title: "入口", default: .schedule) var target: CampusShortcutTarget
    func perform() async throws -> some IntentResult { target.enqueue(); return .result() }
}

struct OpenScannerIntent: AppIntent {
    static var title: LocalizedStringResource = "打开校园扫码"
    static var openAppWhenRun = true
    func perform() async throws -> some IntentResult { CampusShortcutTarget.scanner.enqueue(); return .result() }
}
struct OpenRechargeIntent: AppIntent {
    static var title: LocalizedStringResource = "校园卡充值"
    static var openAppWhenRun = true
    func perform() async throws -> some IntentResult { CampusShortcutTarget.recharge.enqueue(); return .result() }
}
struct OpenHotWaterIntent: AppIntent {
    static var title: LocalizedStringResource = "打开饮水热水"
    static var openAppWhenRun = true
    func perform() async throws -> some IntentResult { CampusShortcutTarget.hotWater.enqueue(); return .result() }
}
struct OpenExpressIntent: AppIntent {
    static var title: LocalizedStringResource = "打开取件码"
    static var openAppWhenRun = true
    func perform() async throws -> some IntentResult { CampusShortcutTarget.expressPDD.enqueue(); return .result() }
}
