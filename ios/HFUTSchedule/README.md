# 聚在工大 iOS 工程

当前版本 **1.2.0**，运行于 iOS 17.0 及以上。使用 SwiftUI；支持相应系统能力时采用 Liquid Glass，较低版本使用 Material 降级样式。

本次同步的上游范围为 2026-10-01 至 2026-11-14：正式版 4.21.4.1，加开发分支 `b3cb252e44f024720f6f8fb6216ad076550ee119`。完整记录见 [上游审计](../../docs/ios/upstream-audit-2026-11-14.md)，实现状态见 [MIGRATION.md](MIGRATION.md)。

## 工程组成

| 位置 | 内容 |
| --- | --- |
| `HFUTSchedule/` | 四栏 SwiftUI 应用、教务 / 校园接口、个人日程与备份 |
| `HFUTScheduleWidget/` | 大号周课表 WidgetKit 扩展 |
| `Shared/` | 周课表共享模型、存储通道与小组件视图 |
| `HFUTScheduleTests/` | 解析、时间规则、存储、校车、AI 与天气回归测试 |
| `project.yml` | XcodeGen 工程定义；新增文件后重新生成工程 |
| `scripts/` | 构建、本机签名及私有快照工具 |

## 构建与测试

建议 Xcode 27.x，先安装 XcodeGen：

```sh
brew install xcodegen
cd ios/HFUTSchedule
xcodegen generate
```

未签名设备构建：

```sh
xcodebuild -project HFUTSchedule.xcodeproj -scheme HFUTSchedule \
  -configuration Release -sdk iphoneos \
  -derivedDataPath build/ReleaseCheck \
  CODE_SIGNING_ALLOWED=NO build
```

生成公共未签名 IPA，可从仓库根目录运行：

```sh
./ios/HFUTSchedule/scripts/build_unsigned_ipa.sh
```

产物位于 `dist/HFUTSchedule-iOS-1.2.0-unsigned.ipa`。IPA 必须另外签名后才能安装到 iPhone；本流程不依赖 Apple 账号，也不自动安装设备。

模拟器测试使用本机已有目标。先执行 `xcrun simctl list devices available`，再从工程目录运行：

```sh
xcodebuild -project HFUTSchedule.xcodeproj -scheme HFUTSchedule \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -derivedDataPath build/SimulatorTests \
  CODE_SIGNING_ALLOWED=NO test
```

目标名称按本机可用模拟器调整。`HFUTSchedule` 共享 scheme 关联 `HFUTScheduleTests`。测试使用构造样例、临时目录和注入传输；DeepSeek 与 QWeather 测试不访问真实 API，也不消耗用户额度。

本次最终命令、测试数量、构建与资源核验结果统一见 [1.2.0 更新说明的验证章节](../../docs/ios/1.2.0.md#验证)。

## 认证与数据

- `CASLoginClient` 使用与上游一致的原生 CAS 请求链；`AcademicClient` 处理直连、WebVPN、重定向及正常 HTML 学籍页面。
- 多学籍优先主修学籍，未标注培养类型时回退首个卡片。所选卡片的学籍标识必须为有效数字；校验失败时停止，不继续挑选其他卡片。
- 教务登录成功后尝试从官方账户页获取教务密码，使用钥匙串保存。网络设置提供刷新与官方修改密码页面入口；不会在备份中导出密码。
- 考试仍保留原生详情列表，并联动课程表与聚焦；按日期与结束时间判断显示，考试不使用个人截止事项的 72 小时规则。
- 个人日程、课程使用原子文件写入。文件损坏时显示恢复提示并保留原文件；失败的保存不应先替换内存数据。
- v2 备份包含课程、个人日程和白名单偏好。旧课程数组仍能导入；Cookie、密码、API Key、学生身份信息不在备份内。

## DeepSeek

AI 助手使用用户在「选项 → 网络 → DeepSeek」配置的 Key，保存在 `AppSecretStore.Account.aiAPIKey`。请求与上游一致：`POST https://api.deepseek.com/chat/completions`，默认 `deepseek-flash`，另支持 `deepseek-v4-pro`。

网页摘要由工具栏按钮触发，读取当前页面 `innerText` 后进入 AI 对话页；发送前可查看正文。URL 查询参数会被移除，正文最多附带 24,000 字，并作为 JSON 网页资料封装。对话仅保留在当前页面，发送失败保留草稿。

## 天气

普通构建默认使用无密钥的 Open-Meteo 实时天气。天气卡片打开和风天气官方详情，预警区提供合肥或宣城的官方预警链接。

`CampusWeatherClient` 支持由集成方显式传入自己的 `QWeatherConfiguration`，按上游解析 `weather/now`、`warning/now` 和 `fxLink`。本仓库未配置该账户，也不从机器寻找凭据；没有复制上游作者的 JWT 签名配置。只有成功的空预警响应才表示暂无预警，未配置或失败均指引查看官方页面。

## 小组件与公共产物

小组件实现了 App Group、共享钥匙串和包内 JSON 的读取通道。实际共享能力由签名权限、团队和 entitlement 配置决定，需要按自己的签名环境核对，不能仅凭存在 App Group 标识就假定共享已生效。

公共源码中的 `ScheduleSnapshot.json` 保持为空数组。公共 IPA 也必须包含空快照；首次安装时显示「打开 App 同步课表」引导，点击组件打开应用。正常数据写入后请求重载时间线；时间线另有短间隔和跨日刷新策略，最终刷新时机由 WidgetKit 决定。

带个人快照的构建和临时签名工具仅用于本机。发布前应核对 App 中有 `stu.json`、嵌入的 `HFUTScheduleWidget.appex`，且快照为空；不要将旧的个人安装包作为公共附件。

## 当前验收边界

单元测试与构建验证覆盖代码路径和构造响应。真实校方账号、不同学籍、直连 / WebVPN 网络、实时校车及个人签名后的真机小组件仍需在线验收；AI 服务也需由使用者自行配置 DeepSeek 后验证。具体迁移与未完成项见 [MIGRATION.md](MIGRATION.md)。
