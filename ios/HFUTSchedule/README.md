# 聚在工大 iOS 工程

当前版本 **1.3.1 build 8**（2026-11-25），最低 iOS 17.0，发布使用 **iOS 27.2 SDK**。见 [更新与验收](../../docs/ios/1.3.1.md)、[逐项功能清单](../../docs/ios/parity-acceptance.md)。

## 工程组成

| 位置 | 内容 |
| --- | --- |
| `HFUTSchedule/` | 四栏 SwiftUI 应用、教务 / 校园接口、个人日程与备份 |
| `HFUTScheduleWidget/` | 周课表、聚焦小组件及实时活动扩展 |
| `Shared/` | 周课表共享模型、存储通道与小组件视图 |
| `HFUTScheduleTests/` | 解析、时间规则、存储、校车、AI 与天气回归测试 |
| `HFUTSchedule/Resources/tessdata/` | 原生登录验证码识别使用的公开 Tesseract 模型 |
| `project.yml` | XcodeGen 工程定义；新增文件后重新生成工程 |
| `scripts/` | 构建、本机签名及私有快照工具 |

## 构建与测试

使用包含 iOS 27.2 SDK 的 Xcode，先安装 XcodeGen。Swift Package Manager 固定依赖 `SwiftyTesseract/libtesseract` 0.2.0（Tesseract 4.1.0），首次构建会解析该依赖：

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

产物位于 `dist/HFUTSchedule-iOS-1.3.1-unsigned.ipa`。侧载用包再执行 `./scripts/build_resignable_ipa.sh`，得到 `HFUTSchedule-iOS-1.3.1-resignable.ipa`。后者只有无证书的 ad-hoc 共享声明元数据，必须由自己的侧载工具重新签名后安装；两个流程均不读取 Apple 账号或描述文件，也不自动安装设备。

模拟器测试使用本机已有目标。先执行 `xcrun simctl list devices available`，再从工程目录运行：

```sh
xcodebuild -project HFUTSchedule.xcodeproj -scheme HFUTSchedule \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -derivedDataPath build/SimulatorTests \
  CODE_SIGNING_ALLOWED=NO test
```

目标名称按本机可用模拟器调整。`HFUTSchedule` 共享 scheme 关联 `HFUTScheduleTests`。测试使用构造样例、临时目录和注入传输；DeepSeek 与 QWeather 测试不访问真实 API，也不消耗用户额度。

本次最终命令、测试数量、构建与资源核验结果统一见 [1.3.1 更新说明的验证章节](../../docs/ios/1.3.1.md#真机与自动化验证)。

## 原生登录验证码自动填写

CAS 直连和 WebVPN 原生登录页共用本地 Tesseract 识别能力：对当前会话已经取得的图片先灰度处理，再按单行文字识别并尝试填入输入框。图片刷新后重新识别，旧图片的结果不能回填新表单。用户手动修改优先；关闭自动填写开关后取消任务并忽略迟到结果。失败时仍可手动输入或刷新图片，不自动提交登录，也不向任意网页注入识别逻辑。

模型随 App 内置于 `HFUTSchedule/Resources/tessdata/captcha.traineddata`，来自本仓库 `tools/Captcha-Ocr/成品/`，以 `captcha` 语言加载，无需额外下载或向 OCR 服务上传图片。已核对 Android 下载使用的 `eng.traineddata`、仓库训练模型与 iOS 内置资源：均为 11,697,722 字节，SHA-256 一致。相同模型不保证两端每张图片的识别结果相同；模型来源、具体摘要、上游核对范围与验证边界详见 [1.2.3](../../docs/ios/1.2.3.md)。

## WebVPN 网址工具

「查询中心 → WebVPN」提供普通链接转 WebVPN 和代理链接还原。两页均有示例、输入清空、转换及结果复制 / 打开 / 清除；转换完全在本机完成，不要求登录或网络。输入需带完整 `http://` 或 `https://`，还原只接受本校的有效代理链接。端口、编码路径、查询参数与片段分别保留；损坏数据明确报错。

WebVPN 结果在本机保存的会话票据可用后打开；没有可用会话时先引导登录。还原后的普通结果没有 WebVPN 登录限制，但若全局 WebVPN 已开启，打开阶段仍会按全局设置再次转换。

全局开关仅存内存、默认关闭，只在已保存的票据通过可用性检查后允许开启。开启后作用于普通网页打开入口，已有代理链接保持原样；CAS 登录、教务认证页面和认证回调不参与全局转换。签名、SDK、Duo 和小组件仍沿用 1.2.1 方案，不能把本次离线 URL 测试视为真实校方会话验收。

## 认证与数据

- `CASLoginClient` 使用与上游一致的原生 CAS 请求链；`AcademicClient` 处理直连、WebVPN、重定向及正常 HTML 学籍页面。
- 多学籍优先主修学籍，未标注培养类型时回退首个卡片。所选卡片的学籍标识必须为有效数字；校验失败时停止，不继续挑选其他卡片。
- 教务登录成功后尝试从官方账户页获取教务密码，使用钥匙串保存。网络设置提供刷新与官方修改密码页面入口；不会在备份中导出密码。
- 考试仍保留原生详情列表，并联动课程表与聚焦；按日期与结束时间判断显示，考试不使用个人截止事项的 72 小时规则。
- 个人日程、课程使用原子文件写入。文件损坏时显示恢复提示并保留原文件；失败的保存不应先替换内存数据。
- v3 备份包含课程、日程、成绩、考试、学籍、收藏、来源缓存和兼容偏好；可导入旧 JSON 及 Android ZIP。备份可能包含个人信息，Cookie、密码和 API Key 不导出。

## DeepSeek

AI 助手使用用户在「选项 → 网络 → DeepSeek」配置的 Key，保存在 `AppSecretStore.Account.aiAPIKey`。请求与上游一致：`POST https://api.deepseek.com/chat/completions`，默认 `deepseek-flash`，另支持 `deepseek-v4-pro`。

网页摘要由工具栏按钮触发，读取当前页面 `innerText` 后进入 AI 对话页；发送前可查看正文。URL 查询参数会被移除，正文最多附带 24,000 字，并作为 JSON 网页资料封装。对话仅保留在当前页面，发送失败保留草稿。

## 天气

普通构建默认解析和风天气官方公开实时天气及预警页面；失败时回退 Open-Meteo 与官方预警链接。解析失败不会显示为暂无预警。

`CampusWeatherClient` 支持由集成方显式传入自己的 `QWeatherConfiguration`，按上游解析 `weather/now`、`warning/now` 和 `fxLink`。本仓库未配置该账户，也不从机器寻找凭据；没有复制上游作者的 JWT 签名配置。只有成功的空预警响应才表示暂无预警，未配置或失败均指引查看官方页面。

## 小组件与公共产物

### 1.2.1 同步流程

- 启动加载已有本地课表后重新发布快照，前台返回和设置页手动发送也使用同一流程。缺失 / 损坏的本地文件不能发布空数据覆盖已有共享快照。
- v2 快照包含课程、版本标识、时间和 `termStart`；小组件优先使用随 App 发送的学期开始日期。兼容旧数组快照。
- 合法的空课表具有独立含义：清空课表后发送的有效空快照会压过旧数据，不回退显示旧包内课程。
- 共享通道区分「写入成功」和「扩展已读取」。只有扩展读取后写回、且对应当前快照版本的 ACK 回执，才确认读取；App 自己回读不算扩展确认。
- 「选项 → 偏好与配置 → 桌面小组件」显示同步状态并可手动发送。WidgetKit 的实际刷新仍由系统调度，请求重载不等于已显示。

### 签名与验证

两个目标的 `keychain-access-groups` 均使用 `$(AppIdentifierPrefix)com.xiaozhangwangxue.hfutschedule.ios`。运行时不再写死 `kSecAttrAccessGroup`，写入使用当前签名授予的默认首组。重签名必须保留 Widget 扩展，并让同一个已授权共享组成为两个目标的首组。不能假设 App ID prefix 始终等于团队标识。Apple 的 [Keychain Sharing 配置文档](https://developer.apple.com/documentation/xcode/configuring-keychain-sharing) 说明了动态前缀、两个目标共组和默认首组规则。

`scripts/build_temporary_signed_ipa.sh` 从两个描述文件提取实际前缀与授权组，不再将维护者团队写入 entitlement；签名后调用 `verify_widget_signing.sh`。如果使用其他工具重签，可在工程目录执行：

```sh
./scripts/verify_widget_signing.sh /absolute/path/to/signed.ipa
```

该脚本只读检查签后 App / Widget、entitlement、描述文件授权及签名完整性，只报告结构和共组状态。**它必须用于已签名包**，不能用未签名公共 IPA 证明共享可用，也不能代替安装后 ACK 验证。不保证所有侧载工具会保留扩展或共同访问组。

App Group 容器仍按实际签名授权决定是否可用；不能根据免费 / 付费账号身份一概判断。当前 Apple [iOS 能力表](https://developer.apple.com/help/account/reference/supported-capabilities-ios) 在免费 Apple Developer 列列出 App Groups 与 Keychain Sharing，最终仍需核对描述文件、签名和容器访问。

### 公共包

公共源码中的 `ScheduleSnapshot.json` 保持为空数组。公共 IPA 也必须包含空快照，不能注入维护者个人课表来掩盖共享通道问题。未同步时显示打开 App 的引导；已取得有效空课表时按无课状态处理。

带个人快照的构建和临时签名工具仅用于本机。发布前应核对 App 中有 `stu.json`、嵌入的 `HFUTScheduleWidget.appex`，且快照为空；不要将旧的个人安装包作为公共附件。

## Duo 与可变窗口

校园信息网格按当前窗口提供的宽度和动态字体计算列数，并限制内容最大宽度，不依赖设备名称或固定屏幕尺寸。窗口变宽、收窄、旋转和 Duo 动态窗口变化时重新布局。本次 SDK 构建和窗口场景的实际验证结果见 1.2.1 发布说明，硬件验收单列。

## 当前验收边界

单元测试与构建验证覆盖代码路径和构造响应。本版已验证本人账号的直连登录、信息门户 / 第二课堂和电费；其他学籍、WebVPN 完整业务、实时校车及所有签名方式下的真机小组件仍需分别验收；AI 服务也需由使用者自行配置 DeepSeek 后验证。具体迁移与未完成项见 [MIGRATION.md](MIGRATION.md)。
