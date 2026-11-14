# HFUT-Schedule 上游更新审计（2026-11-14）

## 范围与固定版本

- 源仓库：[Chiu-xaH/HFUT-Schedule](https://github.com/Chiu-xaH/HFUT-Schedule)，默认开发分支 `dev`。
- 截止快照：[`b3cb252e44f024720f6f8fb6216ad076550ee119`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/b3cb252e44f024720f6f8fb6216ad076550ee119)，2026-11-13 23:06:59 +08:00。
- 审计窗口：2026-10-01 00:00:00 至 2026-11-14（+08:00），按提交时间检索，共 **65 条提交、5 次正式发布**。包含 11 月 12–13 日尚未发布的 DeepSeek/网页联动更新。
- 上游 Android 源码与接口改动已合并到 iOS 分支；SwiftUI 行为按平台适配，不能把 Kotlin 合并等同于 iOS 功能实现。
- 时间表中的日期是 Git committer 日期；发布日期按 GitHub `published_at` 转 +08:00。例如 v4.21.3 的 UTC 发布日在 10 月 25 日，+08:00 为 10 月 26 日。

## 发布对照

| 发布 | +08:00 日期 | 变化摘要 |
| --- | --- | --- |
| [v4.21.2.2](https://github.com/Chiu-xaH/HFUT-Schedule/releases/tag/v4.21.2.2) | 2026-10-05 | 平均成绩排除规则选项；分组图表崩溃修复；GitHub 链接与转场/显示调整。 |
| [v4.21.2.3](https://github.com/Chiu-xaH/HFUT-Schedule/releases/tag/v4.21.2.3) | 2026-10-10 | 公告 WebVPN 路由、生日通知；Android 导航底栏和转专业菜单崩溃修复。 |
| [v4.21.3](https://github.com/Chiu-xaH/HFUT-Schedule/releases/tag/v4.21.3) | 2026-10-26 | 日程克隆、教务密码自动获取与修改入口、实时校车；Room 失败隔离及 Android 外观适配。 |
| [v4.21.4](https://github.com/Chiu-xaH/HFUT-Schedule/releases/tag/v4.21.4) | 2026-11-01 | 创新班登录；一卡通首卡快捷设置、天气详情、自由选周日期修复；Android 环境/兼容性适配。 |
| [4.21.4.1](https://github.com/Chiu-xaH/HFUT-Schedule/releases/tag/4.21.4.1) | 2026-11-09 | 主修/微专业学籍选择；首页首次时间刷新；部分横屏与宽屏页面。 |

## iOS 行为对照与 owning source

| 范围 | 上游依据 | SwiftUI 适配重点 |
| --- | --- | --- |
| 教务学籍 | `logic/network/repo/JxglstuRepository.kt` | 重定向和正常 HTML 页面均支持；`.student-panel-block` 中优先 `培养类型=主修` 的 `button[value]`，未标注时回退首卡；只接受数字。 |
| 教务密码 | `network-api/.../inf/JxglstuService.kt`、`JxglstuRepository.kt`、`cube/sub/EditPasswordScreen.kt` | GET `my/account`，取 `form#save-form input#plainPassword` 的 value；自动刷新和手动刷新；修改密码打开该账户页。 |
| 成绩 | `screen/grade/grade/jxglstu/JxglstuGrade.kt` | 开关默认 false；开启时保留被排除的课程参与本地平均成绩，并即时重算总学分。 |
| 生日 | `screen/home/cube/sub/MyAPIItem.kt` | 仅在既非生日又无远端公告时隐藏整个区块；生日祝福与远端公告分别决定显示。 |
| 个人日程 | `screen/home/focus/funiction/AddEvent.kt` | 克隆生成新记录；当前实际入口为单日/截止项。**多日期组件和重复日程页面仍未启用**；云端共建在本范围中被暂时下线。 |
| 校车 | `screen/home/search/function/community/bus/BusScreen.kt`、`logic/network/repo/OthersRepository.kt` | 出行/所有安排；日期、起终点选择与交换；自然星期分组、今天严格过滤已发车班次；立即算首帧并每整分钟刷新；假期/调休提示查看公告，不能自行替换星期类别。 |
| 聚焦时间/首卡 | `screen/home/focus/FocusUI.kt`、`enumeration/FocusSchoolCardQuickButton.kt` | 进入立即更新时间，随后每分钟刷新；校园卡首卡快捷按钮为无/充值/付款码。 |
| 课表周跳转 | `nav/window/TimeTablePreviewWindow.kt` | 周数和顶部日期使用同一状态源同步变更。 |
| 天气 | `screen/home/search/function/other/life/QWeather.kt`、`network-api/.../qweather/*Response.kt` | 保留 `fxLink`，天气与预警可点击详情。 |
| AI | `logic/network/repo/DeepSeekRepository.kt`、`enumeration/ChatModel.kt`、`ui/util/WebViewFactory.kt` | `https://api.deepseek.com/chat/completions`，Bearer 用户 Key；默认上游模型 `deepseek-flash`，另枚举 `deepseek-v4-pro`；网页归纳仅由用户点按触发，提取 `document.body.innerText`。 |
| 宽屏/显示 | `nav/destination/FailRateDetailDestination.kt`、`HolidayDestination.kt`、`ui/util/layout/AdaptiveUi.kt` | 使用 SwiftUI 系统适配；Android Compose 实现不直接搬入。 |

上述源码相对路径中的 `logic/`、`screen/`、`nav/` 默认位于 `app/src/main/java/com/hfut/schedule/`，网络 DTO 位于 `network-api/src/main/java/com/hfut/schedule/network/api/`。

## Android 专用、工程改动与未启用内容

- APK 下载、安装、更新完成动画、Gradle/构建网络修复仅属于 Android 构建与分发；iOS 使用自身签名与 IPA 流程。
- Room 升级异常隔离属于 Android 数据库栈；iOS 使用自己的持久化实现。需保留平台对应的读写失败提示/恢复能力，不能引入 Room。
- Compose BottomBar 数组越界、特定 Android 低版本虚线、主题鲜艳度、渐进模糊回弹、LargeButton 间距及 Husk 转译检测都不应把 Android 实现写入原生 SwiftUI。相应 iOS 页面需用原生布局和导航验证。
- KMP 方案文档、日期多选组件、group_id 预留、新重复日程雏形属于研究或未启用代码；不能以新增功能名义对用户开放未经上游启用的流程。
- 代码规范、日志、CPU/内存工具、注释、统计图及更新日志属于基础设施/文档。完整源码保留在合并中，不应伪装成新的 iOS 用户功能。

## 完整提交清单

分类用于移植审查，不表示所有 Android 专用提交完全没有可借鉴的用户体验；详细平台边界见上文。每行链接固定提交，可直接核对完整 diff。

| 提交 | +08:00 日期 | 原始标题 | 分类 | 核对说明 / 主要文件 |
| --- | --- | --- | --- | --- |
| [`0c5352d3`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/0c5352d3beec98c2e62fb5600dabb6d2bf29253c) | 2026-10-02 | bugfix:部分带小组的培养方案发生崩溃 | 共同逻辑 / iOS 适配 | 图表堆叠分组防越界；并非培养方案接口格式改变。 |
| [`3d5d3aa4`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/3d5d3aa4f3b54456c8051296c35ceca710f8b1fe) | 2026-10-02 | refactor:StringHelper | 工程/文档/发布 | `GithubRepository.kt`, `NewsRepository.kt` |
| [`fdb50d8b`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/fdb50d8bcb6d6af13bb44a2c84cbf81a9c4be408) | 2026-10-03 | update:Chart | 工程/文档/发布 | `AboutDeveloper.kt`, `Support.kt` |
| [`bebb90a8`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/bebb90a87473dc58641b4c8748b622cd4a072fc0) | 2026-10-03 | feature:忽略平均成绩的排除计算 | 共同逻辑 / iOS 适配 | 本地平均成绩是否纳入被排除的课程；默认维持原筛选。 |
| [`5d49448e`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/5d49448e247f574713f5cb5ad1c3009bf13dabae) | 2026-10-05 | release:4.21.2.2 | 工程/文档/发布 | `SharedNavProxy.kt`, `GlobalUiStateHolder.kt` |
| [`fb14186b`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/fb14186bf42d7c3bae2549190740f7e937277bae) | 2026-10-06 | bugfix:偶见部分网络下无法构建 | Android 专用 | 构建、文档或发布元数据；见提交 diff。 |
| [`7b0f0c9f`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/7b0f0c9fd2b14e84928865995594aca263d41fc8) | 2026-10-06 | bugfix:修复屏幕尺寸变动时新底栏数组越界崩溃 | Android 专用 | `NavigationBarItemData.kt` |
| [`9c66e69c`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/9c66e69cc29a6707a6a2f2aed3e0123b4b376b07) | 2026-10-08 | bugfix:转专业列表右上角菜单选择通知公告后发生崩溃 | Android 专用 | `NewsActivityUI.kt` |
| [`acc27066`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/acc27066e339731b30f7f3ffde0e3ee0a5267353) | 2026-10-09 | bugfix:检查WebVpn登陆状态时打开通知公告网页时异常使用了WebVpn | 共同逻辑 / iOS 适配 | 访问公告时的 WebVPN 路由需按资源判断，不能跟随瞬时登录检查状态。 |
| [`eedfb090`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/eedfb09010ff611760919c9c6b0facecaca8d848) | 2026-10-10 | bugfix:修复生日不显示重要通知 | 共同逻辑 / iOS 适配 | 生日卡片独立于远端公告 show；无公告时生日仍显示。 |
| [`7205eaad`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/7205eaadcf814b66b2de36e6f877b66e56b5b7c6) | 2026-10-10 | release:4.21.2.3 | 工程/文档/发布 | 构建、文档或发布元数据；见提交 diff。 |
| [`297c42cf`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/297c42cf653ab5f8834f212003f26b0f7a4e8201) | 2026-10-13 | update:日程新功能设计方案 | 研究/未启用 | `AddEventDestination.kt`, `AddEvent.kt` |
| [`3c9fd34f`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/3c9fd34f370ad46b0f02a1e4656c2028c154943b) | 2026-10-16 | refactor:部分代码替换 | 工程/文档/发布 | `SuccessActivity.kt`, `AesKeyInterceptor.kt` |
| [`699bd23b`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/699bd23b3c88425dde9150429a62eedbf48b6088) | 2026-10-16 | feature:日程克隆 | 共同逻辑 / iOS 适配 | 编辑事件可复制为新事件；不沿用原记录 id。 |
| [`3b39c00e`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/3b39c00ec5d0c9f462f13b77a2f486d950d45cc7) | 2026-10-16 | feature:分离解耦日期选择器 & offline:暂时下线云端共建（需要更新后台） | 共同逻辑 / iOS 适配 | 日期选择器拆分；云端共建暂时下线，不能宣称云端新流程已可用。 |
| [`f6398d8d`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/f6398d8df88f9eece8ee60431c01edb2ac233428) | 2026-10-17 | feature:日期多选组件 | 研究/未启用 | 组件存在，但最新 AddEvent 的多日期结果和调用均被注释，未启用。 |
| [`18573a75`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/18573a75d348e24432f7275b074d123f1cd699a7) | 2026-10-19 | feature:适配日期多选组件的窄屏自适应 | 研究/未启用 | 未启用的多日期组件窄屏改良。 |
| [`5be211fe`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/5be211fe16247f7de08f25bdff9dab528c4a79ca) | 2026-10-20 | feature:自动获取教务系统密码 | 共同逻辑 / iOS 适配 | my/account 抓取 plainPassword；自动/手动刷新及修改密码网页入口。 |
| [`1d7c7c3b`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/1d7c7c3b43d47d55802c1fcda2b5efd2cfa19803) | 2026-10-20 | feature:为日程预留group_id字段 | 研究/未启用 | group_id 为预留字段；当前新日程写入仍为 null。 |
| [`97c160b5`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/97c160b5580091c993f248534c7e1399a114997f) | 2026-10-20 | feature:Room数据库升级失败后自动禁用，防止影响整个应用 | Android 专用 | Android Room 升级失败后禁用数据库，避免整应用崩溃；iOS 不使用 Room。 |
| [`6c778511`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/6c77851167e492a5317a4e286735454201925b7a) | 2026-10-21 | feature:下线范围选取 | 共同逻辑 / iOS 适配 | 普通日程单日期，截止项选截止日；不开放多日范围批量添加。 |
| [`27ce756a`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/27ce756a717d3704bf5d18c8658da4c21a7995e5) | 2026-10-22 | update:新日程添加页面雏形 | 研究/未启用 | 新重复日程界面草案；不得将未启用分支作为已发布能力。 |
| [`c6127e1f`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/c6127e1fcec98d9f951df1ec4501d9003c60117d) | 2026-10-22 | feature:精简文案 | 工程/文档/发布 | `LoginUI.kt` |
| [`fb0b0de0`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/fb0b0de01bb853de24281e9d0a9727954eb718ab) | 2026-10-23 | feature:继续调整AddEvent的UI&UX | 共同逻辑 / iOS 适配 | 当前启用的添加/编辑事件文案与布局；重复日程仍未启用。 |
| [`6de1887f`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/6de1887f73fb6c2e335ae6fac9221d625b0b190a) | 2026-10-23 | feature:底栏高度与侧边对齐 | Android 专用 | `DataStoreManager.kt`, `BottomBar.kt` |
| [`e82a896c`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/e82a896c35ad5625d07cc1cc63054a996c09be9c) | 2026-10-23 | feature:课程表周数选取浮窗适配大屏 | 共同逻辑 / iOS 适配 | 周数预览在宽屏的交互；SwiftUI 使用系统自适应呈现。 |
| [`fa7b9a57`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/fa7b9a573b054b2460987797cf8cdde3c4a1cc50) | 2026-10-23 | refactor:冗余代码优化 | 工程/文档/发布 | `CustomEventDao.kt`, `CustomEventDaoImplSafely.kt` |
| [`19eb49e0`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/19eb49e03c646fe5eaed0099948d6f9e4947f1eb) | 2026-10-23 | feature:校车新UI | 共同逻辑 / iOS 适配 | 校车出行/所有安排及起终点选择。 |
| [`3b773790`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/3b7737902c4aa8c8b1c8f3bfb3ab35abf53de54a) | 2026-10-24 | feature:校车新UI（2） | 共同逻辑 / iOS 适配 | 校车日期、方向交换、线路显示。 |
| [`2c49fa1d`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/2c49fa1dea74d7fa21db1eb930330f4482f2d46e) | 2026-10-25 | bugfix:主题色黑白下大卡片无背景 | Android 专用 | `Theme.kt` |
| [`eb3ae627`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/eb3ae6271d58b5af34e019c23203adadf41ed436) | 2026-10-25 | feature:新校车 | 共同逻辑 / iOS 适配 | 按星期及未发车班次过滤，假期/调休公告提示。 |
| [`5adf7629`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/5adf76293df81f4c89aeb611d27f33f68246f36a) | 2026-10-25 | release:4.21.3 | 工程/文档/发布 | 构建、文档或发布元数据；见提交 diff。 |
| [`9dd84111`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/9dd841114ed49c4c671b4487f729d84abc599966) | 2026-10-26 | feature:优化聚焦一卡通和电费金额的滚动显示 | Android 专用 | `SchoolCard.kt`, `Electric.kt` |
| [`44b03b64`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/44b03b6413b4d2b1b0b3ae9f96ca3e8db8a5c9b8) | 2026-10-26 | bugfix:课程表自由选择周数后顶部日期值错误 | 共同逻辑 / iOS 适配 | 跳任意周数时同步 weekSwap 与顶部日期。 |
| [`d28db249`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/d28db24939d27a1e2d4b122f490ce0e36d32c05d) | 2026-10-26 | feature:恢复查询中心一卡通右侧按钮始终显示 | 共同逻辑 / iOS 适配 | 查询中心校园卡的快捷入口始终可见。 |
| [`03bb6ede`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/03bb6edecc43a8844bc3c2fc2ce082b04655f207) | 2026-10-27 | feature:支持自定义聚焦一卡通右侧快捷按钮 | 共同逻辑 / iOS 适配 | 聚焦校园卡快捷按钮：无/充值/付款码。 |
| [`9f4673d5`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/9f4673d545dc04854febf9742265d742163a5e16) | 2026-10-28 | update:注释微调 | 工程/文档/发布 | `DataStoreManager.kt` |
| [`a2564c57`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/a2564c57dc4487b2cc77db8c9c8dfff5caec5c38) | 2026-10-29 | feature:优化部分UI和Toast的文案提示 | 共同逻辑 / iOS 适配 | 原生页面/提示文案细化。 |
| [`5db810ad`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/5db810adda8468d160ac4f3569a92c19a8c82548) | 2026-10-29 | feature:半优化深色模式网页注入效果 | 共同逻辑 / iOS 适配 | 网页深色样式在可见提交时注入，避免完成后才闪切。 |
| [`94c8f7f2`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/94c8f7f2c8197326e2722f936ccfd2326b38d76e) | 2026-10-30 | feature:新增若干性能工具类 | Android 专用 | `TemperatureUtil.kt`, `AppMemoryUtil.kt` |
| [`38e4ed97`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/38e4ed971ff8b0cbd124f97fb61bad9bbda34141) | 2026-10-30 | feature:和风天气点击事件 | 共同逻辑 / iOS 适配 | 实时天气和预警保留响应 fxLink 并支持打开详情。 |
| [`dfb6d3aa`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/dfb6d3aa6534a29b88f8cc17c62437452978067b) | 2026-10-31 | feature:ComponentStack | Android 专用 | `ComponentStack.kt` |
| [`395906c8`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/395906c864924b205f07bb4b890508a01d253abc) | 2026-11-01 | bugfix:判定非合理KV值并纠正 & feature:一些环境信息 | Android 专用 | Android 版本能力开关纠错、环境信息；iOS 不复用 Android 系统阈值。 |
| [`d144d9a4`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/d144d9a47dbc0561d024a82357061053f4f77d2b) | 2026-11-01 | bugfix:修复低版本系统中虚线分割线被渲染为实线 | Android 专用 | `Divider.kt` |
| [`ef1a8bc1`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/ef1a8bc1c71f241f048a4831cac59eb18e6a3907) | 2026-11-01 | feature:支持检测App是否在iOS Husk转译环境运行 | Android 专用 | 检测 Android 在 Husk 环境；原生 SwiftUI 不需要转译检测。 |
| [`be1a278c`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/be1a278c29295364a26becf1626d33468121b3f9) | 2026-11-01 | feature:完善日志 | Android 专用 | `LaunchRequest.kt` |
| [`49e0a1f0`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/49e0a1f0ae3c0864a0a27811e375ce65184cb79d) | 2026-11-01 | feature:适配创新班 & release:4.21.4 | 共同逻辑 / iOS 适配 | HTTP 200 多学籍页面也提取 studentId。 |
| [`37c7b452`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/37c7b45295392e802a3787797a423b7c5af8a757) | 2026-11-01 | update:规范更新日志 | 工程/文档/发布 | 构建、文档或发布元数据；见提交 diff。 |
| [`b138433f`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/b138433fd04e652639937ef086225272966b52ae) | 2026-11-02 | update:代码规范查缺补漏 | 工程/文档/发布 | `CommunityRepository.kt`, `GithubRepository.kt` |
| [`01dc1695`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/01dc1695971529a9dd1346ecebddb9b01922186f) | 2026-11-03 | bugfix:聚焦首页自动刷新机制首次被推迟1分钟 | 共同逻辑 / iOS 适配 | 首页时间先立即更新，再每分钟刷新。 |
| [`107a9155`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/107a9155504968b8ec7de3e109b6201a792ce607) | 2026-11-04 | feature:大屏适配FailRateDetailDestination | 共同逻辑 / iOS 适配 | 挂科率明细的大屏适配。 |
| [`115a2a86`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/115a2a8620ba0252d7f725bbf472f38eac38e16c) | 2026-11-04 | feature:大屏适配HolidayDestination | 共同逻辑 / iOS 适配 | 假期安排的大屏适配。 |
| [`215a807d`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/215a807d89b042e5184afd382383541385c546c4) | 2026-11-05 | feature:清理无用提交 | 工程/文档/发布 | `AutoKey.kt` |
| [`4d0bab08`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/4d0bab081a7c78d0bbee79957218cc8334080901) | 2026-11-06 | bugfix:修复部分页面滑动到底后回弹时，顶部渐进模糊渲染异常 | Android 专用 | `AboutDeveloper.kt`, `JxglstuGrade.kt` |
| [`15cf731a`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/15cf731ab52898b10388fa8c345d327429d4e422) | 2026-11-07 | update:方案调研 | 研究/未启用 | `DeepLink.kt`, `CornerSettingsDestination.kt` |
| [`07a53023`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/07a53023290f5f90fbf95d9433649159549d8e14) | 2026-11-07 | feature:优化LargeButton统一间距 | Android 专用 | `LargeButton.kt`, `SettingsItemsUI.kt` |
| [`81bf63ed`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/81bf63edc76718554c3fcb91e20dfcf4e352afb6) | 2026-11-07 | feature:优化下载更新 | Android 专用 | `LargeButton.kt`, `UpdateUI.kt` |
| [`f14a5a34`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/f14a5a34df1dceb74e59182b0f8adafc3bd5a114) | 2026-11-07 | feature:优化更新完成的动效减少掉帧 | Android 专用 | `Starter.kt`, `UpdateSuccessScreen.kt` |
| [`8c5b6618`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/8c5b6618e0effe120d96cb4af3d45081483e42c2) | 2026-11-09 | feature:优化无用的网络请求vm.getLessonTimes | 共同逻辑 / iOS 适配 | 移除无用 getLessonTimes 请求与不再依赖的布局字段。 |
| [`cfea8cec`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/cfea8cec0622d2a1e8c3a933df1fae93dc748ab5) | 2026-11-09 | bugfix:修复多学籍账号误用微专业学籍 | 共同逻辑 / iOS 适配 | 多学籍优先培养类型=主修，回退首卡；防止取到微专业。 |
| [`eaaaad38`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/eaaaad3874a17f120faad3a9926865b3eee21cac) | 2026-11-09 | update:更新日志 | 工程/文档/发布 | `MyApplication.kt` |
| [`6b439306`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/6b4393066fc2072b85833a54c89b29a82cf18ca2) | 2026-11-09 | release:4.21.4.1 | 工程/文档/发布 | `FailRateDetailDestination.kt`, `HolidayDestination.kt` |
| [`d63c6f6c`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/d63c6f6ce8b9f36483d69d8541b5bc77ab454321) | 2026-11-11 | update:更新命名错误 | 工程/文档/发布 | `DeepLink.kt`, `CourseClassmatesDestination.kt` |
| [`719fd981`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/719fd98133b5350bfbf9b431f7277e114bc67fa1) | 2026-11-12 | feature:DeepSeek Api | 共同逻辑 / iOS 适配 | DeepSeek POST chat/completions，Bearer 用户 Key；消息角色/内容。 |
| [`b3cb252e`](https://github.com/Chiu-xaH/HFUT-Schedule/commit/b3cb252e44f024720f6f8fb6216ad076550ee119) | 2026-11-13 | feature:网页支持联动DeepSeek | 共同逻辑 / iOS 适配 | 网页取 innerText，经用户点按后转入 AI 归纳；支持预填后自动请求。 |

## 可复核检索

```sh
git log upstream/dev --since='2026-10-01 00:00:00 +0800' \
  --until='2026-11-15 00:00:00 +0800' --reverse \
  --format='%H %cd %s' --date=iso
git diff 5d49448e..b3cb252e -- app network-api common-logic common-ui
```

`5d49448e` 是原 iOS 1.1.0 已跟进的 4.21.2.2 基线；完整 65 条清单仍覆盖 10 月 1 日起的整个窗口，包含已在旧 iOS 基线内的内容，避免只检查新 release 而漏掉未发布提交。

## iOS 1.2.0 实现状态矩阵

下表补充 SwiftUI 的实际实现与平台差异；前文 65 条上游提交保持完整。应用源码路径相对于 `ios/HFUTSchedule/HFUTSchedule/`；小组件与 `Shared/` 相对于工程目录 `ios/HFUTSchedule/`。实现完成不等于真实账号或签名设备验收通过，本次最终验证结果统一见 [1.2.0 更新说明](1.2.0.md#验证)。

| 行为 | iOS 状态 | 对应源码与限制 |
| --- | --- | --- |
| 创新班与主修学籍 | 已实现，待真实账号验收 | `Services/AcademicClient.swift`：兼容重定向和正常 HTML，主修卡优先，未标注培养类型时回退首个卡片；所选编号未通过数字校验时停止，不改选其他卡片。 |
| 教务密码获取 / 刷新 / 修改 | 已实现，待真实账号验收 | `Services/AcademicClient.swift`、`Views/SettingsScreens.swift`、`Views/AcademicStudentInfoView.swift`：从官方账户页读取，钥匙串保存，官方改密页面入口。 |
| 成绩排除选项 | 已实现，待真实账号验收 | `Views/AcademicRecordsView.swift`、`Services/AppSettingsStore.swift`：按开关即时重算平均成绩与学分，维持默认排除行为。 |
| 考试在课程表与聚焦显示 | 已实现，待真实账号与真机验收 | `Views/ScheduleView.swift`、`Views/DashboardView.swift`、考试模型：课表按日期投影到所选周；聚焦列出未来及当天未结束考试，**无 72 小时限制**。本项也落实用户本次明确要求。 |
| 实时校车与日期筛选 | 已实现，待在线验收 | `Services/CampusBusService.swift`、`Views/CampusUpdateViews.swift`：出行 / 所有安排、起终点交换、自然星期、今天过滤已发车班次及分钟刷新。 |
| 普通日程 / 截止事项 / 克隆 | 已实现 | `Models/CustomEvent.swift`、`Services/CustomEventStore.swift`、`Views/CustomEventViews.swift`：克隆使用新标识，跨天普通日程按天投影。未开放未启用的批量多日期、重复日程或云端共建流程。 |
| 聚焦首帧 / 前台刷新 | 已实现，待真机交互验收 | `Views/DashboardView.swift`：进入即更新时间，随后刷新；前台返回重新计算。 |
| 校园卡快捷按钮 | 已实现，待付款入口验收 | `Views/DashboardView.swift`、`Views/SettingsScreens.swift`：无 / 充值 / 付款码。 |
| 生日与通知 | 已实现，待真实账号验收 | `Views/DashboardView.swift`、生日判定逻辑：生日与远端公告独立显示。 |
| 备份 v2 与持久化保护 | 已实现 | `Services/ScheduleBackupPayload.swift`、`Services/ScheduleStore.swift`、`Services/CustomEventStore.swift`：课程、事件和白名单偏好，兼容旧课程数组，原子写入、损坏保留及错误提示；敏感认证数据不导出。 |
| DeepSeek 与网页联动 | 已实现，测试不访问真实 API | `Services/DeepSeekClient.swift`、`Views/AIAssistantView.swift`、`Views/PortalWebView.swift`：上游 Flash / Pro 和请求形状；用户 Key；主动提取正文，进入 AI 页面后由用户发送，可先查看资料。此处增加发送前查看步骤，未采用上游预填后自动请求。 |
| 天气详情 / 预警 | **数据源差异**，官方入口已实现 | `Services/CampusWeatherClient.swift`、`Views/FeatureDetailView.swift`：默认 Open-Meteo 实时天气；和风官方详情与预警入口。QWeather 自有配置客户端可解析 now / warning / `fxLink`；未复制上游作者 JWT 签名配置，默认无内嵌预警流，不把未连接当作无预警。 |
| Widget 与公共包 | 已实现，待签名后真机验收 | `HFUTScheduleWidget/`、`Shared/`：空态、点击打开应用、刷新策略与写入容错；公共快照为空，实际数据共享取决于签名和 entitlement 配置。 |
| 开发者环境与平台布局 | 原生适配 | 维护页环境信息及 SwiftUI 布局；未引入 Android Room、Husk、Compose、APK 更新实现。 |
| 既有设置的旧缺口 | 保留边界 | `defaultCourseSource`、`autoRefreshLogin` 等设置不凭 UI 存在声明端到端已完成；智慧社区源切换、后台登录等仍需独立审计和验收。 |

发布方式为源代码与自行签名安装的 IPA。自动化测试、构建、包内资源和敏感数据检查是本地验证；校方在线请求、真实账号、实时服务和设备最终验收仍分别记录，不合并成“全部功能已验收”。
