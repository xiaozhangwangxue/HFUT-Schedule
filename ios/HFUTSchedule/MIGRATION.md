# iOS 功能迁移矩阵

状态含义：`可用` 已有 iOS 实现；`入口可用` 可通过校方网页或外部应用完成；`迁移中` 尚未达到 Android 版完整度。

| 区块 | 状态 | iOS 实现 |
| --- | --- | --- |
| 首页与功能导航 | 可用 | SwiftUI + Liquid Glass |
| 手动课表与离线保存 | 可用 | Codable 本地存储 |
| 系统日历导出 | 可用 | EventKit |
| 二维码扫描 | 可用 | VisionKit DataScanner |
| 统一身份认证 | 入口可用 | WKWebView + 校方 CAS，会话由 WebKit 管理 |
| 48 项校园服务入口 | 入口可用 | 校方网页、WebVPN 或对应外部应用 |
| 教务课表自动同步 | 迁移中 | 待移植 CAS 会话与教务解析 |
| 成绩、考试、培养方案 | 迁移中 | 待移植网络模型与解析 |
| 校园卡、网费、电费、洗浴 | 迁移中 | 当前可访问门户，待原生账单视图 |
| 图书馆、校车、宿舍评分 | 迁移中 | 当前可访问门户，待原生数据视图 |
| 通知与考试提醒 | 迁移中 | 待接入 UserNotifications |
| Android 快捷设置磁贴 | 迁移中 | 将改为 App Intents / 快捷指令 |
| Android 桌面小组件 | 迁移中 | 将改为 WidgetKit |
| APK 增量更新 | 已替换 | iOS 采用 TestFlight/App Store 版本分发 |
