# 聚在工大 · iOS（HFUT-Schedule）

合肥工业大学校园服务 App 的原生 **iOS / SwiftUI** 版本，基于 [Chiu-xaH/HFUT-Schedule](https://github.com/Chiu-xaH/HFUT-Schedule) 移植，保留上游 Android 源码与接口文档。

当前版本：**1.2.1**（2026-11-14），修复升级或重新签名后「App 有课程，小组件仍无数据」的问题，并补充同步状态和手动发送入口。

上游同步基线保留自 1.2.0：已核对 **2026-10-01 至 2026-11-14** 的全部 65 条提交和 5 次正式发布，覆盖正式版 **4.21.4.1** 和开发分支 [`b3cb252e`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/b3cb252e44f024720f6f8fb6216ad076550ee119)。

- [iOS 1.2.1 小组件修复说明](docs/ios/1.2.1.md)
- [iOS 1.2.0 更新历史](docs/ios/1.2.0.md)
- [上游完整更新审计与 iOS 对照](docs/ios/upstream-audit-2026-11-14.md)
- [iOS 迁移状态与边界](ios/HFUTSchedule/MIGRATION.md)

## 下载与安装

发布文件见 [GitHub Releases](https://github.com/xiaozhangwangxue/HFUT-Schedule/releases)。侧载安装优先下载 `HFUTSchedule-iOS-1.2.1-resignable.ipa`：它以无证书、无描述文件的 ad-hoc 签名保留 App 与 Widget 的共组声明，供侧载工具读取后重新签名，不能直接安装。另提供纯 `unsigned.ipa` 给自行完整配置签名的构建者。重签名时必须保留 Widget 扩展，并让 App 和 Widget 使用相同的首个 Keychain 共享组；具体工具是否支持该配置需要核验。签名权限、设备登记与有效期由所用签名方式决定。

公共 IPA 不包含个人课表快照、账号、Cookie、密码或 API Key。安装后在 App 内登录并同步自己的数据。`dist/` 是本机构建输出目录，不纳入 Git 源码。

## 1.2.1 小组件与窗口适配

- 恢复启动时发布已有本地课表，回到前台也会重新发送；无需修改课程或重新登录来触发同步。
- 移除共享通道中的固定团队前缀。两个目标使用动态 `AppIdentifierPrefix` 共组，运行时遵循当前签名授予的默认组。
- 快照携带学期开始日期，合法空课表可以覆盖旧数据；写入失败和本地文件损坏不冒充同步成功。
- 「**选项 → 偏好与配置 → 桌面小组件**」可查看发送与读取状态并手动发送。只有小组件返回对应快照的读取回执才确认已读取。
- 发布构建使用 **iOS 27.2 SDK**；网格随当前窗口宽度和动态字体调整，适配 Duo 窗口变化等布局场景。

最终验证结果和重签名要求见 [1.2.1 更新说明](docs/ios/1.2.1.md)。公共包继续不含私人快照；保留的 1.2.0 功能如下。

## 1.2.0 主要更新历史

- **教务认证**：兼容创新班、多学籍页面，优先选择主修学籍；未标注培养类型时回退首个卡片，编号无效即停止。登录后可取回教务系统密码，网络设置提供手动刷新与官方修改密码入口。
- **考试联动**：考试安排同时出现在课程表与聚焦页。聚焦展示所有未来考试和当天尚未结束的考试；课表按考试日期投影到对应周次。
- **个人日程**：普通日程与截止事项可新增、编辑、删除、克隆；克隆保留原记录并生成新标识，跨天普通日程分段显示在课程表。
- **校车**：出行 / 所有安排、日期选择、起终点筛选与交换；今天过滤已经发车的班次，并随时钟刷新。
- **聚焦**：首次进入立即更新时间，支持校园卡「无 / 充值 / 付款码」快捷按钮；生日祝福独立显示。
- **备份**：v2 JSON 包含课表、个人日程与可移植偏好，兼容旧版课程数组；读取损坏时保留原文件，保存失败时提示错误。
- **AI 助手**：原生 DeepSeek 连续对话；网页工具栏可提取正文并进入摘要对话。使用用户自己的 DeepSeek API Key，默认模型 `deepseek-flash`，可选 `deepseek-v4-pro`。
- **天气与小组件**：天气卡片、气象预警可打开官方详情；保留免密钥实时天气来源。周课表小组件补齐空态、点击跳转与刷新策略。

详细交互、数据来源差异和验证边界见 [更新说明](docs/ios/1.2.0.md)。

## 既有功能

- 四个主栏目：**课程表 / 聚焦 / 查询中心 / 选项**。
- 周课表、课程详情、离线手动课程、教务同步、系统日历导出、课程提醒与快捷指令。
- CAS 原生认证与校方会话复用，支持校内直连和校外 WebVPN。
- 成绩与分析、考试、学籍、培养方案、选课、评教、全校课程和空教室查询。
- 48 项校园服务入口，包括校园卡、电费、校园网、洗浴、洗衣（**海乐生活**）、第二课堂、图书馆、宿舍评分、今日校园、慧新易校、费用中心、就业服务与校车。
- 深色模式、外观与偏好设置、设置项搜索和大号 WidgetKit 周课表小组件。

服务的原生实现、网页入口和待验收范围分别列于 [迁移矩阵](ios/HFUTSchedule/MIGRATION.md)。

## 构建

运行要求为 **iOS 17.0 及以上**。发布构建要求包含 **iOS 27.2 SDK** 的 Xcode，并使用 [XcodeGen](https://github.com/yonaskolb/XcodeGen)。在仓库根目录执行：

```sh
./ios/HFUTSchedule/scripts/build_unsigned_ipa.sh
```

或手动构建：

```sh
cd ios/HFUTSchedule
xcodegen generate
xcodebuild -project HFUTSchedule.xcodeproj -scheme HFUTSchedule \
  -sdk iphoneos -configuration Release \
  CODE_SIGNING_ALLOWED=NO build
```

模拟器测试、资源检查和签名说明见 [iOS 工程说明](ios/HFUTSchedule/README.md)。本次最终验证结果统一记录在 [1.2.1 更新说明](docs/ios/1.2.1.md#验证)；1.2.0 验证保留在其历史说明中。

## 目录

```text
app/                         上游 Android 应用
network-api/                 上游接口与数据模型
common-logic/ common-ui/      上游公共模块
docs/update/                 上游更新说明
docs/ios/                    iOS 发布说明与逐提交审计
ios/HFUTSchedule/
  HFUTSchedule/              SwiftUI 应用
  HFUTScheduleWidget/        周课表小组件
  Shared/                    小组件数据与共用视图
  HFUTScheduleTests/         自动化回归测试
  scripts/                   构建及本机签名工具
  project.yml                XcodeGen 工程定义
  dist/                      忽略的本机构建产物
```

## 使用与实现边界

- 真实校方账号、校内 / WebVPN 网络与真机交互仍需逐项验收，测试模型或模拟器构建不能代替在线验收。
- 默认实时天气来自 Open-Meteo，天气详情和预警由和风天气官方页面提供；未配置和风天气接口时不会在 App 内声称「暂无预警」。本项目没有复制上游作者的天气签名凭据。
- DeepSeek 请求仅在用户发送时发起；网页摘要会把页面正文作为资料发送到 DeepSeek，发送前可查看正文。API Key 保存在本机钥匙串。
- 公共包使用空的小组件快照。个人快照、临时签名和设备安装脚本仅用于本机，不用于生成公共发布文件；小组件共享数据需要签名权限与 entitlement 配置匹配。
- App Groups 与 Keychain Sharing 的可用性按 Apple 当前能力表和实际签名判断，不能简单断言免费团队一律不支持 App Groups。参见 [Apple 能力表](https://developer.apple.com/help/account/reference/supported-capabilities-ios) 和 [Keychain 共组配置](https://developer.apple.com/documentation/xcode/configuring-keychain-sharing)。
- 默认课表数据源、自动刷新登录等既有设置不纳入本次“全部功能已完成”的声明，具体限制见迁移矩阵。

## 上游与许可

Android 应用、校方接口整理与上游文档来自 [Chiu-xaH/HFUT-Schedule](https://github.com/Chiu-xaH/HFUT-Schedule)。可查阅 [上游更新日志](docs/update)、[开发者文档](docs/Developer.md)、[校内接口文档](docs/HfutApi.md) 和 [DeepLink 说明](docs/DeepLink.md)。

本仓库沿用 [Apache License 2.0](LICENSE)。
