import AppKit
import SwiftUI

struct MenuBarContentView: View {
  @EnvironmentObject private var appModel: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
        .padding(18)

      Divider()

      VStack(spacing: 10) {
        Button {
          AppWindowCoordinator.shared.showWorkout()
        } label: {
          Label("开始 3 分钟微运动", systemImage: "play.fill")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(AppTheme.accent)
        .controlSize(.large)

        if appModel.settings.isPaused {
          Button("恢复提醒") {
            appModel.resumeReminders()
          }
          .frame(maxWidth: .infinity)
        } else {
          HStack(spacing: 8) {
            Button("推迟 10 分钟") {
              appModel.snoozeTenMinutes()
            }
            .frame(maxWidth: .infinity)

            Button("今天暂停") {
              appModel.pauseUntilTomorrow()
            }
            .frame(maxWidth: .infinity)
          }
        }
      }
      .padding(14)

      Divider()

      VStack(spacing: 2) {
        menuRow("完成记录", systemImage: "chart.bar") {
          AppWindowCoordinator.shared.showDashboard()
        }
        menuRow("设置", systemImage: "gearshape") {
          AppWindowCoordinator.shared.showSettings()
        }
        menuRow("退出小桌伴", systemImage: "power") {
          NSApp.terminate(nil)
        }
      }
      .padding(8)
    }
    .frame(width: 330)
    .background(AppTheme.warmBackground.opacity(0.55))
  }

  private var header: some View {
    HStack(spacing: 13) {
      Image(systemName: "leaf.fill")
        .font(.system(size: 22, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 44, height: 44)
        .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 13))

      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text("小桌伴")
            .font(.headline)
          Spacer()
          Text("今日 \(appModel.todayCompletedCount)/\(appModel.settings.dailyWorkoutGoal)")
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.accent)
        }

        Text(reminderDescription)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var reminderDescription: String {
    if appModel.settings.isPaused {
      return "提醒已暂停至明天"
    }
    guard let nextDue = appModel.nextDue else {
      return "提醒尚未排定"
    }
    return "下次提醒 \(AppFormatters.relative.localizedString(for: nextDue, relativeTo: Date()))"
  }

  private func menuRow(
    _ title: String,
    systemImage: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack {
        Image(systemName: systemImage)
          .frame(width: 20)
        Text(title)
        Spacer()
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .padding(.horizontal, 9)
    .padding(.vertical, 8)
  }
}
