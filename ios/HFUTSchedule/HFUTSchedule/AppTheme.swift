import SwiftUI

enum AppTheme {
    static let accent = Color(red: 0.18, green: 0.48, blue: 0.96)
    static let cyan = Color(red: 0.18, green: 0.78, blue: 0.92)
    static let mint = Color(red: 0.22, green: 0.76, blue: 0.58)
    static let violet = Color(red: 0.55, green: 0.38, blue: 0.94)

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
