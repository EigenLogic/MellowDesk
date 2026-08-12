# MellowDesk Privacy Policy / 小桌伴隐私政策

Effective date / 生效日期: 2026-08-11

Applies to / 适用版本: v0.1.0-beta.1 through v0.1.0-beta.3

## English

### Summary

MellowDesk is designed for local use. The app does not create an account, send analytics, show ads, or upload camera data. Camera access is optional, begins only when you start a NeckEase routine, and can be replaced by manual counting.

### Camera processing

- Frames are processed in memory with AVFoundation and Vision on this Mac.
- Frames are used to estimate face presence and approximate head direction for live counting.
- Video, still images, audio, face templates, and frame-by-frame head angles are not written to disk.
- Camera inputs and outputs are removed when the routine ends, is closed, or the workout window is hidden.
- MellowDesk does not identify who you are and does not perform face recognition.

### Data stored on this Mac

Settings are stored in UserDefaults. They may include the reminder interval, selected weekdays, work hours, sound preference, launch-at-login preference, pause date, daily goal, and the next scheduled reminder.

Workout history is stored as an atomic JSON file in the app's Application Support container. It contains:

- a storage schema version;
- session ID, start and end times, completion status, routine version, and whether the camera was used;
- for each movement, the movement ID, target repetitions, completed repetitions, and completion mode.

Displayed duration is calculated from start and end times. MellowDesk does not store video, photos, audio, identity data, face templates, or per-frame pose samples in workout history.

### Network and third parties

The beta has no network entitlement and no account, cloud sync, advertising, analytics, crash-upload, or telemetry SDK. Camera processing uses Apple system frameworks on the device. Project maintainers do not receive app data through the app.

If you voluntarily use GitHub to open an issue, discussion, security report, or pull request, GitHub's own terms and privacy practices apply to the information you submit.

### Permissions

- **Camera:** optional local movement counting.
- **Notifications:** optional scheduled reminders and reminder actions.
- **Launch at login:** optional menu-bar startup through macOS.

Declining camera access does not block the routine; manual counting remains available.

### Retention and deletion

Settings and history remain in the app container until you change or delete them. Use **Settings → Clear all history** to delete workout history. You can revoke camera and notification permissions in macOS System Settings. Removing local app data is controlled by macOS and the user.

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
- 训练完成、关闭或训练窗口隐藏后，App 会停止摄像头并移除采集输入输出。
- 小桌伴不识别用户身份，也不做人脸识别。

### 保存在本机的数据

设置使用 UserDefaults 保存，可能包括提醒间隔、工作日、工作时段、声音、登录启动、暂停日期、每日目标和下一次提醒时间。

训练历史以原子 JSON 文件保存在 App 的 Application Support 容器中，包含：

- 存储结构版本；
- session ID、开始和结束时间、完成状态、动作内容版本，以及是否使用摄像头；
- 每个动作的动作 ID、目标次数、完成次数和完成模式。

界面中的用时由开始和结束时间计算。训练历史不包含视频、照片、音频、身份信息、人脸模板或逐帧姿态样本。

### 网络与第三方

当前 Beta 没有网络 entitlement，也没有账号、云同步、广告、分析、崩溃上传或遥测 SDK。摄像头处理只使用设备上的 Apple 系统框架。项目维护者不会通过 App 收到用户数据。

如果你主动在 GitHub 提交 Issue、Discussion、安全报告或 pull request，你所提交的信息适用 GitHub 自身的条款和隐私规则。

### 权限

- **摄像头：**可选的本地动作计次。
- **通知：**可选的定时提醒和通知快捷操作。
- **登录启动：**通过 macOS 可选地在登录后启动菜单栏 App。

拒绝摄像头权限不会阻止训练，仍可使用手动计次。

### 保留与删除

设置和历史会保留在 App 容器中，直到用户修改或删除。使用“设置 → 清除所有历史”可删除训练历史。摄像头和通知权限可在 macOS 系统设置中撤销。本地 App 数据的移除由用户和 macOS 控制。

### 保护隐私地报告问题

请勿在公开 Issue 中提交人脸、摄像头录像、含有他人的截图、原始姿态数据或个人训练历史文件。摄像头问题应尽量使用文字描述或合成数据复现。安全或隐私漏洞请按 [SECURITY.md](SECURITY.md) 私密报告。

### 变更与联系

数据处理发生实质变化时，本文件、生效日期和变更记录会同步更新。如有隐私问题，请使用托管本仓库的组织资料页所公布的私密联系方式联系维护者，不要在公开 Issue 中包含敏感细节。
