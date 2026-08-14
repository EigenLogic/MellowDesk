import AppKit
import MellowDeskCore
import SwiftUI

struct MenuBarContentView: View {
  /// The popover is sized by its host, so the optional pelvic-floor row has to be
  /// accounted for there as well.
  static let baseContentSize = NSSize(width: 330, height: 354)
  static let pelvicFloorRowHeight: CGFloat = 46
  static let updateReadyRowHeight: CGFloat = 46

  static func contentSize(for settings: AppSettings, updateReady: Bool = false) -> NSSize {
    NSSize(
      width: baseContentSize.width,
      height: baseContentSize.height
        + (settings.pelvicFloorTrainingEnabled ? pelvicFloorRowHeight : 0)
        + (updateReady ? updateReadyRowHeight : 0)
    )
  }

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

        if appModel.settings.pelvicFloorTrainingEnabled {
          Button {
            appModel.startPelvicFloorBreak()
          } label: {
            Label("开始 2 分钟提肛跟练", systemImage: "slowmo")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
          .tint(AppTheme.accent)
          .controlSize(.large)
        }

        HStack(spacing: 8) {
          Button {
            appModel.recordWaterNow()
            AppWindowCoordinator.shared.dismissStatusMenu()
          } label: {
            Label("喝水打卡", systemImage: "drop.fill")
              .frame(maxWidth: .infinity)
          }

          Button {
            appModel.startManualMovementBreak()
            AppWindowCoordinator.shared.dismissStatusMenu()
          } label: {
            Label("起身动动", systemImage: "figure.walk")
              .frame(maxWidth: .infinity)
          }
        }

        if appModel.settings.isPaused {
          Button("恢复提醒") {
            appModel.resumeReminders()
            AppWindowCoordinator.shared.dismissStatusMenu()
          }
          .frame(maxWidth: .infinity)
        } else {
          Button("今天暂停所有提醒") {
            appModel.pauseUntilTomorrow()
            AppWindowCoordinator.shared.dismissStatusMenu()
          }
          .frame(maxWidth: .infinity)
        }
      }
      .padding(14)

      Divider()

      VStack(spacing: 2) {
        if let version = appModel.readyUpdateVersion {
          menuRow("安装 \(version) 并重启", systemImage: "arrow.down.circle.fill") {
            appModel.installReadyUpdate()
          }
          .foregroundStyle(AppTheme.accent)
        }
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
    .frame(width: Self.baseContentSize.width)
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
          Text("今日 \(appModel.todayCompletedCount) 次")
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.accent)
        }

        Text(
          "颈肩 \(appModel.todayCount(for: .neck)) · 喝水 \(appModel.todayCount(for: .water)) · 起身 \(appModel.todayCount(for: .stand))"
        )
        .font(.caption2.weight(.medium))
        .foregroundStyle(AppTheme.secondaryInk)

        reminderDescription
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  @ViewBuilder
  private var reminderDescription: some View {
    if appModel.settings.isPaused {
      Text("提醒已暂停至明天")
    } else if appModel.activeReminder != nil {
      Text("提醒等待处理中")
    } else if let nextDue = appModel.nextDue {
      HStack(spacing: 0) {
        Text("下次：\(appModel.reminderScheduler.nextActivity.localizedName) ")
        // The relative date Text owns a clock and refreshes as time passes.
        Text(nextDue, style: .relative)
      }
    } else {
      Text("提醒尚未排定")
    }
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
