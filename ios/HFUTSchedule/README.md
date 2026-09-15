# 聚在工大 iOS（SwiftUI）

这是 `HFUT-Schedule` 的原生 iOS 移植工程。界面使用 SwiftUI，并在 iOS 26 及以上采用系统 Liquid Glass；iOS 17–25 使用原生 Material 降级样式。

## 当前基线

- SwiftUI 原生四栏架构：首页、课表、校园服务、我的。
- 与 Android 功能目录对齐的 48 个入口。
- 统一身份认证使用校方网页会话，不在应用内读取或保存密码。
- 支持离线手动课表、系统日历导出、二维码扫描、校园门户浏览和系统快捷指令。
- 支持动态字体、深色模式、减少动态和减少透明度。

教务数据解析、成绩、考试、校园卡账单、通知和小组件仍需继续原生化。入口存在不代表该模块已经达到 Android 版功能完整度，进度以 `MIGRATION.md` 为准。

## 构建

```bash
cd ios/HFUTSchedule
xcodegen generate
xcodebuild -project HFUTSchedule.xcodeproj -scheme HFUTSchedule \
  -sdk iphoneos -configuration Release \
  CODE_SIGNING_ALLOWED=NO build
```

生成可安装 IPA 需要 Apple Developer 账号、证书、App ID 和包含目标设备的描述文件。
