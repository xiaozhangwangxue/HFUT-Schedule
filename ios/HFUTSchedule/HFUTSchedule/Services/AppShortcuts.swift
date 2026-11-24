import AppIntents
import Foundation

struct OpenScheduleIntent: AppIntent {
    static var title: LocalizedStringResource = "打开课表"
    static var description = IntentDescription("在聚在工大中直接打开本周课表。")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set("schedule", forKey: "pendingDestination")
        return .result()
    }
}

struct OpenCampusServicesIntent: AppIntent {
    static var title: LocalizedStringResource = "打开校园服务"
    static var description = IntentDescription("打开聚在工大的校园服务中心。")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set("services", forKey: "pendingDestination")
        return .result()
    }
}

struct OpenCampusNetworkIntent: AppIntent {
    static var title: LocalizedStringResource = "打开校园网"
    static var description = IntentDescription("打开合肥工业大学校园网自助服务。")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set("services", forKey: "pendingDestination")
        UserDefaults.standard.set(4, forKey: "pendingFeatureID")
        return .result()
    }
}

struct OpenLibraryIntent: AppIntent {
    static var title: LocalizedStringResource = "打开图书馆"
    static var description = IntentDescription("打开合肥工业大学图书馆。")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set("services", forKey: "pendingDestination")
        UserDefaults.standard.set(19, forKey: "pendingFeatureID")
        return .result()
    }
}

/// 付款码快捷方式（对应上游「扫码支付的快捷方式」）。
struct OpenPayCodeIntent: AppIntent {
    static var title: LocalizedStringResource = "打开付款码"
    static var description = IntentDescription("直接打开慧新易校付款码，用于扫码支付。")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set("services", forKey: "pendingDestination")
        UserDefaults.standard.set(44, forKey: "pendingFeatureID")
        UserDefaults.standard.set(true, forKey: "pendingOpenPayCode")
        return .result()
    }
}

struct HFUTAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenScheduleIntent(),
            phrases: ["在 \(.applicationName) 中打开课表", "用 \(.applicationName) 看课表"],
            shortTitle: "打开课表",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: OpenCampusServicesIntent(),
            phrases: ["打开 \(.applicationName) 的校园服务"],
            shortTitle: "校园服务",
            systemImageName: "square.grid.2x2.fill"
        )
        AppShortcut(
            intent: OpenCampusNetworkIntent(),
            phrases: ["用 \(.applicationName) 打开校园网"],
            shortTitle: "校园网",
            systemImageName: "wifi"
        )
        AppShortcut(
            intent: OpenLibraryIntent(),
            phrases: ["用 \(.applicationName) 打开图书馆"],
            shortTitle: "图书馆",
            systemImageName: "books.vertical.fill"
        )
        AppShortcut(
            intent: OpenPayCodeIntent(),
            phrases: ["打开 \(.applicationName) 的付款码", "用 \(.applicationName) 扫码支付"],
            shortTitle: "付款码",
            systemImageName: "barcode"
        )
        AppShortcut(intent: OpenCampusTargetIntent(), phrases: ["打开 \(.applicationName) 的校园快捷入口"], shortTitle: "校园快捷入口", systemImageName: "square.grid.2x2")
        AppShortcut(intent: OpenScannerIntent(), phrases: ["用 \(.applicationName) 扫码"], shortTitle: "扫码", systemImageName: "qrcode.viewfinder")
        AppShortcut(intent: OpenRechargeIntent(), phrases: ["用 \(.applicationName) 充值校园卡"], shortTitle: "校园卡充值", systemImageName: "yensign.circle")
        AppShortcut(intent: OpenHotWaterIntent(), phrases: ["用 \(.applicationName) 打开热水"], shortTitle: "饮水热水", systemImageName: "drop")
        AppShortcut(intent: LoginCampusNetworkIntent(), phrases: ["用 \(.applicationName) 登录校园网"], shortTitle: "登录校园网", systemImageName: "wifi")
    }

    static var shortcutTileColor: ShortcutTileColor { .blue }
}
