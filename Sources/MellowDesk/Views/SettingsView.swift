import AppKit
import Foundation
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
        privacySection
      }
      .padding(28)
    }
    .background(AppTheme.warmBackground.opacity(0.55))
    .confirmationDialog(
      "确定清除所有完成记录？",
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
      Label("提醒", systemImage: "bell")
        .font(.headline)

      HStack {
        Text("间隔")
        Spacer()
        Picker("提醒间隔", selection: binding(\.reminderIntervalMinutes)) {
          Text("30 分钟").tag(30)
          Text("45 分钟").tag(45)
          Text("50 分钟").tag(50)
          Text("60 分钟").tag(60)
          Text("90 分钟").tag(90)
        }
        .labelsHidden()
        .frame(width: 150)
      }

      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("每日目标")
          Text("用于桌面记录，不影响动作判定")
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

  private var privacySection: some View {
    VStack(alignment: .leading, spacing: 13) {
      Label("隐私与数据", systemImage: "hand.raised")
        .font(.headline)
      Text("摄像头画面只在本机内存中用于实时动作计数，不录制、不保存、不上传。历史仅保存训练时间、内容版本、逐动作目标与完成次数、计次模式和是否使用摄像头。")
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
