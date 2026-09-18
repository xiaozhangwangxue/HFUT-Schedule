# 聚在工大 iOS（SwiftUI）

这是 `HFUT-Schedule` 的原生 iOS 移植工程。界面使用 SwiftUI，并在 iOS 26 及以上采用系统 Liquid Glass；iOS 17–25 使用原生 Material 降级样式。

## 当前基线

- SwiftUI 原生四栏架构：首页、课表、校园服务、我的。
- 与 Android 功能目录对齐的 48 个入口。
- 统一身份认证使用校方网页会话，不在应用内读取或保存密码。
- 支持离线手动课表、教务课表同步、成绩与考试同步、课表备份恢复、上课提醒、系统日历导出、二维码扫描、校园门户浏览和系统快捷指令。
- 支持动态字体、深色模式、减少动态和减少透明度。

教务课表、成绩和考试同步已经完成第一阶段代码迁移，仍需使用真实校方账号完成真机验证。高级成绩分析、考试提醒、校园卡账单仍需继续原生化。入口存在不代表该模块已经达到 Android 版功能完整度，进度以 `MIGRATION.md` 为准。

## 周课表小组件

`HFUTScheduleWidget` 是大号（systemLarge）桌面小组件，一屏显示周一到周五的全部课程，配色与尺寸层级对齐应用内课表页。

- 数据通道按可用性回退：App Group → 共享钥匙串 → 包内 `ScheduleSnapshot.json`。
- 免费个人团队不支持 App Groups，因此默认走共享钥匙串（描述文件的 `TEAM.*` keychain 分组可覆盖），应用每次保存课表都会刷新小组件。
- 包内快照由 `scripts/sync_widget_snapshot.sh` 从真机拉取，保证即使共享通道失效也能显示真实课表。
- `scripts/finish_widget_install.sh` 一键完成快照刷新、描述文件申请、临时签名、真机安装并输出 IPA。

## 构建

```bash
cd ios/HFUTSchedule
xcodegen generate
xcodebuild -project HFUTSchedule.xcodeproj -scheme HFUTSchedule \
  -sdk iphoneos -configuration Release \
  CODE_SIGNING_ALLOWED=NO build
```

生成可安装 IPA 需要 Apple Developer 账号、证书、App ID 和包含目标设备的描述文件。
