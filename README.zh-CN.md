# 小桌伴 MellowDesk

[English](README.md)

<p align="center">
  <img src="docs/assets/app-icon.png" alt="MellowDesk app icon" width="120">
</p>

> 放在桌边，轻轻陪你过好每个工作日。

**开源 Beta · macOS 13+ · Apache-2.0**

小桌伴（MellowDesk）是一款安静待在菜单栏的原生 macOS 桌面伴侣，用一套低打扰的工作间歇计划，轮换提醒你起身活动、日常补水和完成颈肩微运动，并提供可随时开始的提肛跟练。

```text
统一节奏提醒 → 起身 / 补水 / 颈肩活动 → 本地完成记录
```

小桌伴没有账号、云同步、广告、分析或遥测。只有当你主动开始训练时，摄像头才会开启；任何时候都可以改用手动计次。

## 当前 Beta 已实现

- 菜单栏常驻，可设置工作日、工作时段、提醒间隔、声音、推迟、暂停和登录启动。
- 到点后从菜单栏叶片下方弹出持久提醒，直到选择“开始”“推迟”或“今天暂停”才关闭。
- 本地通知，支持“开始训练”和“推迟 10 分钟”快捷操作。
- 默认每 50 分钟提醒一项，按“起身活动 → 起身补水 → 颈肩微运动”轮换；同一时间只出现一张卡片。
- 两分钟起身活动引导、喝水快捷打卡，以及按口渴和个人习惯补水的非定量提示。
- 颈间三动作：左右缓慢转头、左右轻柔侧屈、轻柔低头并回正。
- 两分钟提肛跟练默认开启，可从菜单栏直接开始，也可在设置中关闭；它不用摄像头、不判断动作，不进入自动提醒轮换，也不写入完成记录。
- 内置 Sparkle 2.9.5 自动更新。默认每天检查一次并在后台下载新版本，经 EdDSA 和 Developer ID 签名验证后提示“安装并重启”或“稍后”；选择“稍后”会在退出小桌伴时安装，全程不用跳转网页。
- 动画引导、当前方向、目标次数、到位/回中反馈和完成结果。
- 本地头部姿态计次，包含中立位校准、逐动作方向适配、滤波、迟滞和完整回中检查。
- 摄像头权限被拒绝、设备不可用或识别不稳定时，可切换为手动计次。
- 仅保存在本机的今日、近 7 天和近 30 天分类完成记录。

## 一分钟了解隐私

- 摄像头画面使用 Apple 框架在内存中处理，不录制、不保存、不上传。
- 小桌伴只在这台 Mac 上保存设置、训练汇总和喝水/起身完成时间，不保存图像、人脸模板、音频或逐帧头部角度。
- 网络访问仅用于读取 raw GitHub 上的签名 appcast，并下载其中指向的小桌伴 GitHub Release ZIP；不发送账号、健康、摄像头、历史、分析、广告、遥测或系统画像数据。
- 你可以随时在设置中清除历史。

在提交涉及隐私的问题前，请阅读完整的 [隐私政策](PRIVACY.md)。

## 动作内容边界

颈间和提肛跟练都是面向一般成年办公人群的短时活动引导，不是医疗器械，不提供诊断、治疗或个体化康复方案。请在舒适范围内完成；如果活动引起不适，请停止。

摄像头阈值是为了方便计次的近似识别阈值，不是医学活动度指标，也不是动作处方。请阅读 [动作内容与依据](docs/EXERCISE_CONTENT.md)，了解内容版本、次数、识别逻辑、参考资料和内容治理规则。

## 运行要求

- macOS 13 或更高版本。
- 摄像头可选；不使用摄像头也可手动计次。

只有从源码构建时，才需要安装与 Swift 5.10 兼容的完整 Xcode。

## 下载

请从 [v0.1.0-beta.5 Release](https://github.com/EigenLogic/MellowDesk/releases/tag/v0.1.0-beta.5)
下载经过 Apple 公证的 macOS 通用版本。Release 同时提供 SHA-256 校验文件。App 使用
EigenLogic Developer ID 签名、启用 Hardened Runtime，并已通过 Apple 公证。

Beta.4 是首个接入 Sparkle 的种子版本。从 beta.3 升级到 beta.4 仍需完成最后一次手动下载和安装；安装 beta.4 后，后续版本可直接在小桌伴内后台下载和安装，不再打开网页。

## 从源码构建

本地源码构建使用 ad-hoc 签名，与 GitHub Release 中的官方公证分发包相互独立。源码和 CI 开发包使用 `cn.eigenlogic.mellowdesk.dev` bundle identifier 和 Dev 名称；正式 Release 继续使用 `cn.eigenlogic.mellowdesk` 和小桌伴正式名称。这样开发版的本地数据和 macOS 隐私权限不会与正式签名版本混用。

构建并打开 App：

```bash
./Scripts/run_debug.sh
```

运行全部自动检查并组装 App：

```bash
./Scripts/check.sh
```

开发产物位于 `build/MellowDesk.app`，bundle identifier 为 `cn.eigenlogic.mellowdesk.dev`，bundle name 为“MellowDesk Dev”，显示名称为“小桌伴 Dev”。正式发布脚本会明确恢复生产 bundle identifier 和名称。

## 首次使用

1. 打开 `MellowDesk.app`；如需定时提醒，请允许通知。
2. 默认计划会在工作时段内轮换提醒起身、补水和颈肩活动；也可从菜单栏手动开始任一项。
3. 两分钟提肛跟练默认显示在菜单栏，也可在设置中关闭；它仅供按需开始，不进入提醒轮换或完成记录。
4. 颈肩微运动可开启摄像头，或改用手动计次。
5. 短暂正视屏幕，建立中立位。
6. 每项动作开始前，先完成一次不计数的小幅适配动作并回正。
7. 跟随动画完成动作。只有到位短停、再可见地回到中立位后才会计次。

## Beta 已知限制

- 摄像头计次有意采用近似识别，表现会受机型、光线、入镜位置和个人动作影响。
- 当前 Beta 的 App 界面仍为中文；项目提供英文文档不代表 App 已完成英文本地化。
- 源码构建的 App 使用本地 ad-hoc 签名；GitHub Release 官方版本已完成 Developer ID 签名与 Apple 公证。
- 除自动测试外，还必须在至少一台真实 MacBook 前置摄像头上完成验收；请使用 [真人摄像头验收清单](docs/TEST_CHECKLIST.md)。

## 项目目录

```text
Sources/MellowDeskCore       动作、校准、计次、统计和提醒日历规则
Sources/MellowDesk           App 生命周期、摄像头、服务、视图模型和 SwiftUI 界面
Tests/MellowDeskCoreTests    Core 确定性测试
Tests/MellowDeskTests        App 层确定性测试
Resources                    Info.plist、沙盒权限和隐私清单
Scripts                      检查、App 组装和本地启动
docs                         产品、技术、动作、测试和发布文档
```

当前仓库包含 **81 个确定性测试**。合成数据自动测试不能替代真实摄像头验收。

## 路线图

后续模块可能包括：

- 午餐和外卖提醒。

路线图只表示探索方向，不代表当前功能或交付承诺。

## 项目文档

- [产品设计](docs/PRODUCT_DESIGN.md)
- [技术设计](docs/TECHNICAL_DESIGN.md)
- [动作内容与依据](docs/EXERCISE_CONTENT.md)
- [真人摄像头验收清单](docs/TEST_CHECKLIST.md)
- [发布流程](docs/RELEASING.md)
- [隐私政策](PRIVACY.md)
- [参与贡献](CONTRIBUTING.md)
- [社区行为准则](CODE_OF_CONDUCT.md)
- [安全政策](SECURITY.md)
- [变更记录](CHANGELOG.md)
- [v0.1.0-beta.5 发布说明](docs/releases/v0.1.0-beta.5.md)
- [v0.1.0-beta.4 发布说明](docs/releases/v0.1.0-beta.4.md)

## 贡献与安全

欢迎提交问题报告、文档改进、测试和范围明确的实现变更。在发起 pull request 前，请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。动作内容变更还需要额外的依据和版本管理。

请勿在公开 Issue 中附上人脸、摄像头录像、原始姿态数据或个人训练历史。安全或隐私漏洞请按 [SECURITY.md](SECURITY.md) 中的私密流程报告。

## 许可证

Copyright 2026 EigenLogic and MellowDesk contributors.

项目使用 [Apache License 2.0](LICENSE)，归属信息见 [NOTICE](NOTICE)。
