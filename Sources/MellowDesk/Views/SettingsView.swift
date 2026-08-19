import AppKit
import Foundation
import MellowDeskCore
import SwiftUI
import UserNotifications

struct SettingsView: View {
  @EnvironmentObject private var appModel: AppModel
  @State private var confirmClearHistory = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        Text("设置")
          .font(.system(size: 27, weight: .bold, design: .rounded))

        reminderSection
        workWindowSection
        generalSection
        updateSection
        pelvicFloorSection
        privacySection
        settingsFooter
      }
      .padding(28)
    }
    .background(AppTheme.warmBackground.opacity(0.55))
    .confirmationDialog(
      "确定清除所有健康记录？",
      isPresented: $confirmClearHistory,
      titleVisibility: .visible
    ) {
      Button("清除记录", role: .destructive) {
        appModel.clearHistory()
      }
      Button("取消", role: .cancel) {}
    } message: {
      Text("此操作无法撤销，但不会改变提醒设置。")
    }
  }

  private var reminderSection: some View {
    VStack(alignment: .leading, spacing: 14) {
      Label("健康计划", systemImage: "heart.text.square")
        .font(.headline)

      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("工作间歇")
          Text("四类活动共用一个提醒节奏")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Picker("提醒间隔", selection: binding(\.reminderIntervalMinutes)) {
          Text("30 分钟").tag(30)
          Text("45 分钟").tag(45)
          Text("50 分钟（均衡）").tag(50)
          Text("60 分钟").tag(60)
          Text("90 分钟").tag(90)
        }
        .labelsHidden()
        .frame(width: 150)
      }

      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("颈肩记录目标")
          Text("仅用于记录，不影响提醒轮换或动作判定")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Stepper(
          "\(appModel.settings.dailyWorkoutGoal) 次",
          value: binding(\.dailyWorkoutGoal),
          in: 1...12
        )
        .frame(width: 118)
      }

      VStack(alignment: .leading, spacing: 9) {
        planRow(number: 1, systemImage: "figure.walk", title: "起身活动 2 分钟")
        planRow(number: 2, systemImage: "drop.fill", title: "起身补水并活动")
        planRow(number: 3, systemImage: "figure.mind.and.body", title: "颈肩微运动 3 分钟")
        Text(
          "按当前间隔，每 \(appModel.settings.reminderIntervalMinutes) 分钟提醒一项；同类活动约每 \(appModel.settings.reminderIntervalMinutes * WellnessPlan.cycleLength) 分钟一次。每个恢复窗只出现一张提醒，避免连续打扰。"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }
      .padding(12)
      .background(AppTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))

      HStack {
        Text(notificationDescription)
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        if appModel.reminderScheduler.authorizationStatus == .denied {
          Button("打开系统设置") {
            openNotificationSettings()
          }
        } else if appModel.reminderScheduler.authorizationStatus == .notDetermined {
          Button("开启通知") {
            Task {
              _ = await appModel.reminderScheduler.requestAuthorization()
              await appModel.reminderScheduler.settingsDidChange(appModel.settings)
            }
          }
        }
      }
    }
    .appCard()
  }

  private var workWindowSection: some View {
    VStack(alignment: .leading, spacing: 14) {
      Label("工作时段", systemImage: "clock")
        .font(.headline)

      HStack {
        Picker("开始", selection: startHourBinding) {
          ForEach(6...14, id: \.self) { hour in
            Text(String(format: "%02d:00", hour)).tag(hour)
          }
        }
        Picker("结束", selection: endHourBinding) {
          ForEach(15...23, id: \.self) { hour in
            Text(String(format: "%02d:00", hour)).tag(hour)
          }
        }
      }

      HStack(spacing: 7) {
        ForEach(weekdayOptions, id: \.value) { option in
          Button(option.label) {
            appModel.updateSettings { settings in
              if settings.workdayWeekdays.contains(option.value) {
                if settings.workdayWeekdays.count > 1 {
                  settings.workdayWeekdays.remove(option.value)
                }
              } else {
                settings.workdayWeekdays.insert(option.value)
              }
            }
          }
          .buttonStyle(.bordered)
          .tint(appModel.settings.workdayWeekdays.contains(option.value) ? AppTheme.accent : .gray)
        }
      }

      if appModel.settings.isPaused {
        Button("立即恢复提醒") { appModel.resumeReminders() }
      } else {
        Button("暂停到明天") { appModel.pauseUntilTomorrow() }
      }
    }
    .appCard()
  }

  private var generalSection: some View {
    VStack(alignment: .leading, spacing: 13) {
      Label("通用", systemImage: "switch.2")
        .font(.headline)

      Toggle("提醒声音", isOn: binding(\.soundEnabled))
      Toggle(
        "登录 Mac 时自动启动",
        isOn: Binding(
          get: { appModel.launchAtLoginService.isEnabled },
          set: { appModel.setLaunchAtLogin($0) }
        )
      )

      if appModel.launchAtLoginService.state == .requiresApproval {
        Text("请在“系统设置 → 通用 → 登录项”中允许小桌伴。")
          .font(.caption)
          .foregroundStyle(AppTheme.warning)
      }
    }
    .appCard()
  }

  private var updateSection: some View {
    VStack(alignment: .leading, spacing: 13) {
      Label("软件更新", systemImage: "arrow.triangle.2.circlepath")
        .font(.headline)

      Toggle(
        "自动下载并安装更新",
        isOn: Binding(
          get: { appModel.automaticUpdatesEnabled },
          set: { appModel.setAutomaticUpdatesEnabled($0) }
        )
      )

      HStack {
        Text("当前版本 \(appModel.currentVersionDisplayText)")
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        Button("现在检查") {
          appModel.checkForUpdatesManually()
        }
      }

      if let version = appModel.readyUpdateVersion {
        HStack {
          Label("\(version) 已下载并验证", systemImage: "checkmark.circle.fill")
            .font(.caption.weight(.medium))
            .foregroundStyle(AppTheme.accent)
          Spacer()
          Button("安装并重启") {
            appModel.installReadyUpdate()
          }
          .buttonStyle(.borderedProminent)
          .tint(AppTheme.accent)
        }
      }

      Text("开启后会在后台检查并下载经过签名验证的新版本，退出小桌伴时自动安装；下载完成后也可以直接选择“安装并重启”。全程不会跳转网页。")
        .font(.caption2)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .appCard()
  }

  private var privacySection: some View {
    VStack(alignment: .leading, spacing: 13) {
      Label("隐私与数据", systemImage: "hand.raised")
        .font(.headline)
      Text("只有颈肩跟练会开启摄像头；画面只在本机内存中用于实时动作计数，不录制、不保存、不上传。历史还会在本机记录喝水与起身活动的完成时间。")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      HStack {
        Button("打开摄像头权限设置") {
          if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")
          {
            NSWorkspace.shared.open(url)
          }
        }
        Spacer()
        Button("清除所有历史", role: .destructive) {
          confirmClearHistory = true
        }
      }
    }
    .appCard()
  }

  private var pelvicFloorSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Label("盆底肌练习", systemImage: "figure.core.training")
          .font(.headline)
        Spacer()
        PillLabel(systemImage: "timer", text: "2 分钟")
      }

      Toggle("启用提肛跟练（含自动提醒）", isOn: binding(\.pelvicFloorTrainingEnabled))

      Text(
        "跟随圆环完成收提、保持和充分放松。四个半分钟依次采用慢速、快速、快快慢和快提慢放节奏，练习过程自然呼吸。"
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      Text("开启后会加入常规提醒轮换；完整练完会进入完成记录和趋势统计。练习不使用摄像头。")
        .font(.caption)
        .foregroundStyle(AppTheme.secondaryInk)

      Text(PelvicFloorRoutine.v1.safetyNotice)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .appCard()
  }

  private var settingsFooter: some View {
    Text("小桌伴 · 只在这台 Mac 上运行")
      .font(.caption2)
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity)
  }

  private var notificationDescription: String {
    switch appModel.reminderScheduler.authorizationStatus {
    case .authorized, .provisional:
      return "系统通知已开启"
    case .denied:
      return "通知已被系统设置拒绝"
    case .notDetermined:
      return "尚未请求系统通知权限"
    @unknown default:
      return "无法读取通知权限"
    }
  }

  private func planRow(number: Int, systemImage: String, title: String) -> some View {
    HStack(spacing: 9) {
      Text("\(number)")
        .font(.caption2.weight(.bold))
        .foregroundStyle(.white)
        .frame(width: 20, height: 20)
        .background(AppTheme.accent, in: Circle())
      Image(systemName: systemImage)
        .foregroundStyle(AppTheme.accent)
        .frame(width: 18)
      Text(title)
        .font(.subheadline.weight(.medium))
    }
  }

  private func openNotificationSettings() {
    let notificationsURL = URL(
      string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
    )
    if let notificationsURL, NSWorkspace.shared.open(notificationsURL) {
      return
    }
    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
  }

  private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
    Binding(
      get: { appModel.settings[keyPath: keyPath] },
      set: { value in
        appModel.updateSettings { $0[keyPath: keyPath] = value }
      }
    )
  }

  private var startHourBinding: Binding<Int> {
    Binding(
      get: { appModel.settings.workStartMinutes / 60 },
      set: { hour in
        appModel.updateSettings { $0.workStartMinutes = hour * 60 }
      }
    )
  }

  private var endHourBinding: Binding<Int> {
    Binding(
      get: { appModel.settings.workEndMinutes / 60 },
      set: { hour in
        appModel.updateSettings { $0.workEndMinutes = hour * 60 }
      }
    )
  }

  private var weekdayOptions: [(label: String, value: Int)] {
    [("一", 2), ("二", 3), ("三", 4), ("四", 5), ("五", 6), ("六", 7), ("日", 1)]
  }
}
