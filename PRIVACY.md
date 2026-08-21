# MellowDesk Privacy Policy / 小桌伴隐私政策

Effective date / 生效日期: 2026-08-21

Applies to / 适用版本: v0.1.0-beta.1 and later / 及后续版本

## English

### Summary

MellowDesk is designed for local use. The app does not create an account, send analytics, show ads, or upload camera data. Camera access is optional, begins only when you start a NeckEase routine, and can be replaced by manual counting.

### Camera processing

- Frames are processed in memory with AVFoundation and Vision on this Mac.
- Frames are used to estimate face presence and approximate head direction for live counting.
- Video, still images, audio, face templates, and frame-by-frame head angles are not written to disk.
- Camera inputs and outputs are removed when the neck routine is completed or skipped. While a neck follow-along is active, clicking the menu-bar leaf keeps that visible routine and its camera session active.
- MellowDesk does not identify who you are and does not perform face recognition.

### Data stored on this Mac

Settings and durable reminder state are stored in UserDefaults. They may include the reminder interval, selected weekdays, work hours, sound preference, launch-at-login preference, pause date, daily goal, the next scheduled reminder, and its position in the stand/hydration/neck/pelvic-floor rotation. Sparkle manages the automatic-check and automatic-download preferences, along with its updater state, directly in the app's standard UserDefaults; MellowDesk does not copy them into workout or wellness history.

Workout history is stored as an atomic JSON file in the app's Application Support container. It contains:

- a storage schema version;
- session ID, start and end times, completion status, routine version, and whether the camera was used;
- for each movement, the movement ID, target repetitions, completed repetitions, and completion mode.

Displayed duration is calculated from start and end times. MellowDesk does not store video, photos, audio, identity data, face templates, or per-frame pose samples in workout history.

Stand-up, hydration, and pelvic-floor completions are stored separately in `wellness-history.json` in the same local Application Support container. It contains a schema version and, for each completion, a random record ID, activity type, completion time, and an optional local reminder source ID used only to prevent duplicate records. It does not contain water volume, exercise measurements, health measurements, or identity data.

### Network and third parties

MellowDesk uses outbound network access only for signed software updates. Sparkle 2.9.5 reads the signed appcast at `https://raw.githubusercontent.com/EigenLogic/MellowDesk/main/appcast.xml` on its configured daily schedule, or when the user starts a manual check in Settings. If a newer version is available, Sparkle downloads the ZIP referenced by that appcast from the public EigenLogic/MellowDesk GitHub Release in the background. It does not open a browser or release page.

Sparkle verifies the signed feed and release archive with EdDSA and verifies the downloaded app's Developer ID code signature before installation. When the update is ready, MellowDesk offers **Install and Relaunch** or **Later**; Later installs the verified update when the app quits. Sparkle's system-profile reporting is disabled. These requests do not contain an account identifier, device identifier, MellowDesk settings, history, health data, camera data, analytics event, advertising identifier, telemetry payload, or system-profile payload. GitHub receives ordinary network metadata such as the source IP address and update-protocol metadata such as the requested URL and applies its own terms and privacy practices.

MellowDesk has no account, cloud sync, advertising, analytics, crash-upload, telemetry, or system-profiling SDK. Camera processing uses Apple system frameworks on the device. Project maintainers receive no app-specific user payload through software updating.

If you voluntarily use GitHub to open an issue, discussion, security report, or pull request, GitHub's own terms and privacy practices apply to the information you submit.

### Permissions

- **Camera:** optional local movement counting.
- **Notifications:** optional scheduled reminders and reminder actions.
- **Launch at login:** optional menu-bar startup through macOS.
- **Network:** outbound access only for the signed raw GitHub appcast and the GitHub Release ZIP described above.

Declining camera access does not block the routine; manual counting remains available.

### Retention and deletion

Settings and history remain in the app container until you change or delete them. Use **Settings → Clear all history** to clear both workout history and stand/hydration/pelvic-floor completion history. You can revoke camera and notification permissions in macOS System Settings. Removing local app data is controlled by macOS and the user.

### Privacy-safe issue reporting

Do not post faces, camera recordings, screenshots containing other people, raw pose data, or personal workout-history files in a public issue. Reproduce camera bugs with a written description or synthetic data whenever possible. Report security or privacy vulnerabilities privately as described in [SECURITY.md](SECURITY.md).

### Changes and contact

Material changes to data handling will update this file, its effective date, and the changelog. For a privacy question, contact the maintainers through the private contact method published on the profile of the organization hosting this repository. Do not include sensitive details in a public issue.

## 中文

### 摘要

小桌伴按本地使用设计。App 不创建账号、不发送分析数据、不展示广告，也不上传摄像头数据。摄像头是可选能力，只有在你主动开始“颈间”训练后才会开启，并可随时改用手动计次。

### 摄像头处理

- 画面使用 AVFoundation 和 Vision 在这台 Mac 的内存中处理。
- 画面只用于判断人脸是否有效，并估算头部方向以进行实时计次。
- 视频、照片、音频、人脸模板和逐帧头部角度不会写入磁盘。
- 颈肩跟练完成或跳过后，App 会停止摄像头并移除采集输入输出。颈肩跟练进行中，点击状态栏叶子会保持跟练面板可见，摄像头也会继续工作。
- 小桌伴不识别用户身份，也不做人脸识别。

### 保存在本机的数据

设置和持久提醒状态使用 UserDefaults 保存，可能包括提醒间隔、工作日、工作时段、声音、登录启动、暂停日期、每日目标、下一次提醒时间，以及它在“起身/补水/颈肩/提肛”轮换中的位置。自动检查、自动下载偏好和更新器状态由 Sparkle 直接保存在 App 的标准 UserDefaults 中；小桌伴不会把这些数据复制进训练或健康活动历史。

训练历史以原子 JSON 文件保存在 App 的 Application Support 容器中，包含：

- 存储结构版本；
- session ID、开始和结束时间、完成状态、动作内容版本，以及是否使用摄像头；
- 每个动作的动作 ID、目标次数、完成次数和完成模式。

界面中的用时由开始和结束时间计算。训练历史不包含视频、照片、音频、身份信息、人脸模板或逐帧姿态样本。

起身、喝水与提肛完成记录单独保存在同一 Application Support 容器的 `wellness-history.json` 中，包含存储结构版本，以及每条记录的随机 ID、活动类型、完成时间和可选的本地提醒来源 ID。来源 ID 只用于防止重复记录；文件不保存饮水量、动作测量值、健康测量值或身份信息。

### 网络与第三方

小桌伴仅为签名软件更新使用出站网络。Sparkle 2.9.5 按配置的每日计划，或在用户从设置中手动检查时，读取 `https://raw.githubusercontent.com/EigenLogic/MellowDesk/main/appcast.xml` 上的签名 appcast。发现新版本后，Sparkle 会在后台下载 appcast 指向的 EigenLogic/MellowDesk 公开 GitHub Release ZIP，不会打开浏览器或 Release 页面。

Sparkle 会用 EdDSA 验证签名 feed 和发布压缩包，并在安装前验证下载所得 App 的 Developer ID 代码签名。更新准备好后，小桌伴提供“安装并重启”或“稍后”；选择“稍后”会在退出 App 时安装已验证的更新。Sparkle 的系统画像上报已关闭。请求不包含账号标识、设备标识、小桌伴设置、历史、健康数据、摄像头数据、分析事件、广告标识、遥测或系统画像 payload。GitHub 会收到来源 IP、请求 URL 等正常网络和更新协议元数据，并按 GitHub 自身的条款和隐私规则处理。

小桌伴没有账号、云同步、广告、分析、崩溃上传、遥测或系统画像 SDK。摄像头处理只使用设备上的 Apple 系统框架；项目维护者不会通过软件更新收到 App 专属的用户数据 payload。

如果你主动在 GitHub 提交 Issue、Discussion、安全报告或 pull request，你所提交的信息适用 GitHub 自身的条款和隐私规则。

### 权限

- **摄像头：**可选的本地动作计次。
- **通知：**可选的定时提醒和通知快捷操作。
- **登录启动：**通过 macOS 可选地在登录后启动菜单栏 App。
- **网络：**仅用于上述签名 raw GitHub appcast 和 GitHub Release ZIP 的出站访问。

拒绝摄像头权限不会阻止训练，仍可使用手动计次。

### 保留与删除

设置和历史会保留在 App 容器中，直到用户修改或删除。使用“设置 → 清除所有历史”可同时清除训练历史和起身/喝水/提肛完成记录。摄像头和通知权限可在 macOS 系统设置中撤销。本地 App 数据的移除由用户和 macOS 控制。

### 保护隐私地报告问题

请勿在公开 Issue 中提交人脸、摄像头录像、含有他人的截图、原始姿态数据或个人训练历史文件。摄像头问题应尽量使用文字描述或合成数据复现。安全或隐私漏洞请按 [SECURITY.md](SECURITY.md) 私密报告。

### 变更与联系

数据处理发生实质变化时，本文件、生效日期和变更记录会同步更新。如有隐私问题，请使用托管本仓库的组织资料页所公布的私密联系方式联系维护者，不要在公开 Issue 中包含敏感细节。
