import MellowDeskCore
import SwiftUI

struct DashboardView: View {
  @EnvironmentObject private var appModel: AppModel
  @State private var historyRange = 7

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        header
        todayCard
        statistics
        historyCard
        recentCard
        privacyNote
      }
      .padding(30)
    }
    .background(AppTheme.warmBackground.opacity(0.55))
    .frame(minWidth: 720, minHeight: 560)
    .alert(
      "小桌伴",
      isPresented: Binding(
        get: { appModel.lastUserFacingError != nil },
        set: { if !$0 { appModel.dismissError() } }
      )
    ) {
      Button("好") { appModel.dismissError() }
    } message: {
      Text(appModel.lastUserFacingError ?? "")
    }
  }

  private var header: some View {
    HStack(alignment: .center) {
      VStack(alignment: .leading, spacing: 5) {
        Text("今天也给颈肩一点活动时间")
          .font(.system(size: 27, weight: .bold, design: .rounded))
          .foregroundStyle(AppTheme.ink)
        Text("每次约 3 分钟，缓慢、舒适地完成。")
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button {
        AppWindowCoordinator.shared.showSettings()
      } label: {
        Image(systemName: "gearshape")
      }
      .buttonStyle(.bordered)
      .help("设置")

      Button {
        AppWindowCoordinator.shared.showWorkout()
      } label: {
        Label("开始一次", systemImage: "play.fill")
      }
      .buttonStyle(.borderedProminent)
      .tint(AppTheme.accent)
      .controlSize(.large)
    }
  }

  private var todayCard: some View {
    HStack(spacing: 28) {
      CompletionRing(
        progress: Double(appModel.todayCompletedCount)
          / Double(max(appModel.settings.dailyWorkoutGoal, 1)),
        completed: appModel.todayCompletedCount,
        target: appModel.settings.dailyWorkoutGoal
      )

      VStack(alignment: .leading, spacing: 9) {
        Text(todayMessage)
          .font(.title3.weight(.bold))
          .foregroundStyle(AppTheme.ink)
        Text(nextReminderText)
          .font(.subheadline)
          .foregroundStyle(.secondary)

        if let last = appModel.lastCompletedAt {
          PillLabel(
            systemImage: "checkmark.circle.fill",
            text: "上次完成 \(AppFormatters.relative.localizedString(for: last, relativeTo: Date()))"
          )
        }
      }
      Spacer()
    }
    .appCard()
  }

  private var statistics: some View {
    HStack(spacing: 14) {
      StatTile(
        title: "近 7 天",
        value: "\(appModel.completedCount(inLastDays: 7)) 次",
        caption: "完成的微运动",
        systemImage: "calendar"
      )
      StatTile(
        title: "近 30 天",
        value: "\(appModel.completedCount(inLastDays: 30)) 次",
        caption: "仅保存在本机",
        systemImage: "chart.bar.fill",
        tint: Color(red: 0.35, green: 0.48, blue: 0.78)
      )
      StatTile(
        title: "连续记录",
        value: "\(appModel.currentStreak) 天",
        caption: "不要求每天满额",
        systemImage: "flame.fill",
        tint: AppTheme.warning
      )
    }
  }

  private var historyCard: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("完成趋势")
          .font(.headline)
        Spacer()
        Picker("时间范围", selection: $historyRange) {
          Text("7 天").tag(7)
          Text("30 天").tag(30)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 150)
      }

      HistoryBarChart(values: appModel.dailyCompletions(days: historyRange))
        .frame(height: 175)
    }
    .appCard()
  }

  private var recentCard: some View {
    VStack(alignment: .leading, spacing: 13) {
      Text("近期完成")
        .font(.headline)

      if appModel.historyStore.recentCompleted(limit: 1).isEmpty {
        HStack(spacing: 10) {
          Image(systemName: "clock")
          Text("完成第一次微运动后，记录会显示在这里。")
        }
        .foregroundStyle(.secondary)
        .padding(.vertical, 12)
      } else {
        ForEach(appModel.historyStore.recentCompleted(limit: 6)) { session in
          HStack(spacing: 12) {
            Image(systemName: "checkmark")
              .font(.caption.weight(.bold))
              .foregroundStyle(.white)
              .frame(width: 25, height: 25)
              .background(AppTheme.accent, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
              Text(sessionTitle(for: session))
                .font(.subheadline.weight(.semibold))
              Text(sessionSubtitle(for: session))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if let endedAt = session.endedAt {
              Text(AppFormatters.dateTime.string(from: endedAt))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
          .padding(.vertical, 5)
        }
      }
    }
    .appCard()
  }

  private var privacyNote: some View {
    HStack(spacing: 11) {
      Image(systemName: "hand.raised.fill")
        .foregroundStyle(AppTheme.accent)
      Text("摄像头仅在训练时开启；画面与姿态数据只在内存中本地处理，不保存、不上传。")
        .font(.caption)
        .foregroundStyle(.secondary)
      Spacer()
    }
    .padding(.horizontal, 4)
  }

  private var todayMessage: String {
    let remaining = max(0, appModel.settings.dailyWorkoutGoal - appModel.todayCompletedCount)
    return remaining == 0 ? "今天的计划已完成" : "今天还可以完成 \(remaining) 次"
  }

  private var nextReminderText: String {
    if appModel.settings.isPaused { return "提醒已暂停至明天" }
    guard let due = appModel.nextDue else { return "提醒将在授权后开始" }
    return "下次提醒：\(AppFormatters.dateTime.string(from: due))"
  }

  private func sessionTitle(for session: WorkoutSession) -> String {
    "完成一组颈部微运动"
  }

  private func sessionSubtitle(for session: WorkoutSession) -> String {
    guard let endedAt = session.endedAt else { return "" }
    return "用时 \(AppFormatters.duration(seconds: endedAt.timeIntervalSince(session.startedAt)))"
  }
}
