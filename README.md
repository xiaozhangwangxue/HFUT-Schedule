# 聚在工大 · iOS（HFUT-Schedule）

合肥工业大学校园服务 App 的原生 **SwiftUI / iOS** 版本，基于 [Chiu-xaH/HFUT-Schedule](https://github.com/Chiu-xaH/HFUT-Schedule) 移植，保留上游 Android 源码、接口文档及 Apache 2.0 许可。

当前版本 **1.3.3 build 10**（2026-11-27），最低 iOS 17，发布使用 **iOS 27.2 SDK**。

- [1.3.3 充值页自动填写手机号](docs/ios/1.3.3.md)
- [1.3.2 校园服务、余额、天气与导航修复](docs/ios/1.3.2.md)
- [1.3.1 登录、闪退及电费修复与真机验证](docs/ios/1.3.1.md)
- [1.3.0 功能补全记录](docs/ios/1.3.0.md)
- [逐项功能核对与实现证据](docs/ios/parity-acceptance.md)
- [GitHub Releases 下载](https://github.com/xiaozhangwangxue/HFUT-Schedule/releases)
- [工程、测试与签名说明](ios/HFUTSchedule/README.md)

## 本版内容

1.3.3 点击洗澡、洗衣余额旁的加号后，复用个人资料手机号，在官方充值网页的手机号输入框出现时自动填入。支持异步表单和稍晚获取手机号的情况；保留已填写或手动修改的内容。自动填写仅用于对应官方收费项目的手机号字段，充值金额和支付仍由使用者操作。

1.3.2 修复校园卡账单与消费分析、邮箱链接、个人信息、课程汇总、网址导航和选课入口的数据处理；挂科率支持点选自己的课程，并在独立页面查看结果。洗澡金额换算修正，自动读取个人资料手机号查询洗澡和洗衣余额，聚焦直接显示余额并提供统一的加号充值入口。

聚焦天气左侧显示今天、右侧显示明天，各自展示最高 / 最低气温，仅有实际预警时在下方单独显示。保留液态玻璃，优化导航目标生命周期、标签切换和日程计算；修复灵动岛圆角区域的文字布局。详见 [1.3.2](docs/ios/1.3.2.md)。

对照 iOS 1.2.3 和上游 dev `9670096e15dd04d561da08aded3828046228d6e3` 的差异清单，补全 119 条缺失 / 部分实现记录，涵盖多来源课表、好友课表、聚焦、学业业务、校园生活、云日程、报告、外观、备份、网页工具和系统集成。核对记录是行为条目数量，不表示 119 个独立页面，也不能当作全服务真机验收通过。

保存每校区宿舍配置后自动分别查询照明和空调电费。每次课表更新强制发布新版本并请求小组件重载，未收到读取回执时有限重试；新增今日 / 明日聚焦组件。系统最终刷新时间和共享权限仍取决于 WidgetKit 与实际重签名。

保留考试在课表 / 聚焦显示、双向 WebVPN 网址转换和本地验证码自动填写。课程表与服务网格按当前窗口宽度布局，支持可变窗口；未将模拟器布局检查称为 Duo 真机验收。

## 安装

侧载优先下载 `HFUTSchedule-iOS-1.3.3-resignable.ipa`，使用自己的工具重新签名。此包仅含无证书、无描述文件的 ad-hoc 共享声明，不能直接安装。需要保留 Widget 扩展，让 App 与 Widget 使用同一个已授权的首个 Keychain 共享组。另提供 unsigned 包与 SHA-256 校验文件。

公共 IPA 快照为空，不含维护者个人课表、登录凭据或描述文件。安装后在 App 内登录并同步自己的数据。应用备份可能包含个人学籍 / 成绩 / 考试数据，备份文件请自行保管，密码、Cookie、API Key 不导出。

## 构建

使用含 iOS 27.2 SDK 的 Xcode 及 XcodeGen：

```sh
./ios/HFUTSchedule/scripts/build_unsigned_ipa.sh
./ios/HFUTSchedule/scripts/build_resignable_ipa.sh
```

具体命令、固定的 OCR 依赖、侧载签名诊断与测试见 [iOS 工程说明](ios/HFUTSchedule/README.md)。本地 `build/`、`dist/` 不纳入 Git。

## 验收范围

源码实现、构造响应测试、模拟器界面和发布包检查记录在 [1.3.3 说明](docs/ios/1.3.3.md) 及历史说明。充值自动填写使用真实 WKWebView 的离线表单验证，未执行真实充值。此前修复构建已通过真实账号只读核验；模拟器截图中的示例数据有明确标记。真机流畅度、选退课 / 评教 / 转专业等在线提交及所有签名方式下的小组件，仍需分别验收。不会将模拟接口或重载调用当作服务器提交成功或桌面已刷新。

天气默认读取官方公开页面，失败可回退免密钥天气及官方预警链接，不复制上游私钥。AI 由使用者配置自己的 DeepSeek Key。Android 系统磁贴、AIDL、APK 更新等平台实现保留差异；上游未启用的业务不伪造提交成功。

## 历史与上游

[1.2.3 验证码](docs/ios/1.2.3.md) · [1.2.2 WebVPN](docs/ios/1.2.2.md) · [1.2.1 小组件与窗口](docs/ios/1.2.1.md) · [1.2.0](docs/ios/1.2.0.md) · [10 月起更新审计](docs/ios/upstream-audit-2026-11-14.md) · [迁移矩阵](ios/HFUTSchedule/MIGRATION.md)

上游：[更新日志](docs/update)、[开发者文档](docs/Developer.md)、[校内接口](docs/HfutApi.md)、[DeepLink](docs/DeepLink.md)。仓库沿用 [Apache License 2.0](LICENSE)。
