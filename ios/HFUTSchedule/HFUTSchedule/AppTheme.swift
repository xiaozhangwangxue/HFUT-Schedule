import UIKit
import SwiftUI

enum AppTheme {
    static let defaultAccent = Color(red: 0.18, green: 0.48, blue: 0.96)
    static let cyan = Color(red: 0.18, green: 0.78, blue: 0.92)
    static let mint = Color(red: 0.22, green: 0.76, blue: 0.58)
    static let violet = Color(red: 0.55, green: 0.38, blue: 0.94)

    /// 主题色支持自定义取色与鲜艳度调节（对应上游「外观-主题色」）。
    private(set) static var accent = defaultAccent

    static func applyAccent(hex: String, saturation: Double) {
        let base = hex.isEmpty ? defaultAccent : (Color(hex: hex) ?? defaultAccent)
        accent = adjusted(base, saturation: saturation)
    }

    /// 恢复上次保存的主题色。
    static func restoreAccent() {
        let hex = UserDefaults.standard.string(forKey: AppSettingsKey.accentHex) ?? ""
        let saturation = UserDefaults.standard.object(forKey: AppSettingsKey.accentSaturation) as? Double ?? 1
        applyAccent(hex: hex, saturation: saturation)
    }

    private static func adjusted(_ color: Color, saturation: Double) -> Color {
        guard saturation != 1 else { return color }
        let uiColor = UIColor(color)
        var hue: CGFloat = 0, saturationValue: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard uiColor.getHue(&hue, saturation: &saturationValue, brightness: &brightness, alpha: &alpha) else { return color }
        return Color(uiColor: UIColor(
            hue: hue,
            saturation: min(1, max(0, saturationValue * CGFloat(saturation))),
            brightness: brightness,
            alpha: alpha
        ))
    }

    static var background: LinearGradient {
        LinearGradient(
            colors: [
                Color(uiColor: .systemBackground),
                Color(uiColor: .secondarySystemBackground),
                AppTheme.accent.opacity(0.10),
                AppTheme.violet.opacity(0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension Color {
    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.replacingOccurrences(of: "#", with: "")
        guard value.count == 6 || value.count == 8, let number = UInt64(value, radix: 16) else { return nil }
        let red, green, blue, alpha: Double
        if value.count == 8 {
            red = Double((number >> 24) & 0xFF) / 255
            green = Double((number >> 16) & 0xFF) / 255
            blue = Double((number >> 8) & 0xFF) / 255
            alpha = Double(number & 0xFF) / 255
        } else {
            red = Double((number >> 16) & 0xFF) / 255
            green = Double((number >> 8) & 0xFF) / 255
            blue = Double(number & 0xFF) / 255
            alpha = 1
        }
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    var hexString: String? {
        let uiColor = UIColor(self)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        return String(format: "%02X%02X%02X",
                      Int(round(red * 255)), Int(round(green * 255)), Int(round(blue * 255)))
    }
}
