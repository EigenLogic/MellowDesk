import MellowDeskCore
import SwiftUI

struct DashboardView: View {
  @EnvironmentObject private var appModel: AppModel
  @State private var historyRange = 7
  @State private var historyActivity: WellnessActivityKind?

  var body: some View {
    GeometryReader { proxy in
      let isCompact = proxy.size.height < 610
      let pagePadding: CGFloat = isCompact ? 18 : 22
      let sectionSpacing: CGFloat = isCompact ? 10 : 12
      let recentWidth = min(max(proxy.size.width * 0.36, 258), 310)

      VStack(alignment: .leading, spacing: sectionSpacing) {
        header
        todayCard
        summaryStrip

        HStack(alignment: .top, spacing: sectionSpacing) {
          historyCard
            .frame(maxWidth: .infinity, maxHeight: .infinity)

          recentCard(limit: isCompact ? 4 : 6)
            .frame(width: recentWidth)
            .frame(maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
        .layoutPriority(1)
      }
      .padding(pagePadding)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 3) {
        Text("今天也照顾好自己")
          .font(.system(size: 25, weight: .bold, design: .rounded))
          .foregroundStyle(AppTheme.ink)
        Text("起身、补水、颈肩和提肛跟练，按一个节奏轻松完成。")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer(minLength: 12)

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
        Label("颈肩微运动", systemImage: "play.fill")
      }
      .buttonStyle(.borderedProminent)
      .tint(AppTheme.accent)
      .controlSize(.large)
    }
  }

  private var todayCard: some View {
    HStack(spacing: 14) {
      VStack(alignment: .leading, spacing: 4) {
        Text("今日状态")
          .font(.headline)
          .foregroundStyle(AppTheme.ink)

        Text(nextReminderText)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.85)

        if let last = appModel.lastCompletedAt {
          HStack(spacing: 3) {
            Image(systemName: "checkmark.circle.fill")
            Text("上次")
            Text(last, style: .relative)
          }
          .font(.caption2.weight(.medium))
          .foregroundStyle(AppTheme.accent)
        } else {
          Text("完成一次后，这里会留下记录")
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
      }
      .frame(minWidth: 180, idealWidth: 205, maxWidth: 230, alignment: .leading)

      Divider()
        .frame(height: 48)

      todayMetric(.stand)
      todayMetric(.water)
      todayMetric(.neck)
      todayMetric(.pelvicFloor)
    }
    .appCard(padding: 14)
  }

  private func todayMetric(_ activity: WellnessActivityKind) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Label(activity.localizedName, systemImage: activity.systemImage)
        .font(.caption.weight(.semibold))
        .foregroundStyle(AppTheme.accent)
        .lineLimit(1)
      Text(todayCountText(for: activity))
        .font(.title3.weight(.bold))
        .foregroundStyle(AppTheme.ink)
        .monospacedDigit()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }

  private var summaryStrip: some View {
    HStack(spacing: 0) {
      summaryMetric(
        title: "近 7 天",
        value: "\(appModel.completedCount(inLastDays: 7)) 次",
        systemImage: "calendar",
        tint: AppTheme.accent
      )

      Divider()
        .padding(.vertical, 2)

      summaryMetric(
        title: "近 30 天",
        value: "\(appModel.completedCount(inLastDays: 30)) 次",
        systemImage: "chart.bar.fill",
        tint: Color(red: 0.35, green: 0.48, blue: 0.78)
      )

      Divider()
        .padding(.vertical, 2)

      summaryMetric(
        title: "连续记录",
        value: "\(appModel.currentStreak) 天",
        systemImage: "flame.fill",
        tint: AppTheme.warning
      )
    }
    .appCard(padding: 10)
  }

  private func summaryMetric(
    title: String,
    value: String,
    systemImage: String,
    tint: Color
  ) -> some View {
    HStack(spacing: 9) {
      Image(systemName: systemImage)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(tint)
        .frame(width: 28, height: 28)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

      VStack(alignment: .leading, spacing: 1) {
        Text(title)
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(value)
          .font(.subheadline.weight(.bold))
          .foregroundStyle(AppTheme.ink)
          .monospacedDigit()
      }
      Spacer(minLength: 4)
    }
    .padding(.horizontal, 12)
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .combine)
  }

  private var historyCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        Text("完成趋势")
          .font(.headline)

        Spacer(minLength: 4)

        Picker("活动类型", selection: $historyActivity) {
          Text("全部").tag(Optional<WellnessActivityKind>.none)
          ForEach(WellnessActivityKind.allCases, id: \.self) { activity in
            Text(activity.localizedName).tag(Optional(activity))
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 108)

        Picker("时间范围", selection: $historyRange) {
          Text("7 天").tag(7)
          Text("30 天").tag(30)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 126)
      }

      HistoryBarChart(
        values: appModel.dailyCompletions(
          days: historyRange,
          activity: historyActivity
        )
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(maxHeight: .infinity, alignment: .top)
    .appCard(padding: 14)
  }

  private func recentCard(limit: Int) -> some View {
    let items = appModel.recentWellnessItems(limit: limit)

    return VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("近期完成")
          .font(.headline)
        Spacer()
        if !items.isEmpty {
          Text("最近 \(items.count) 次")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }

      if items.isEmpty {
        Spacer(minLength: 0)
        VStack(spacing: 8) {
          Image(systemName: "clock")
            .font(.title3)
          Text("完成第一次工作间歇后，记录会显示在这里。")
            .font(.caption)
            .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        Spacer(minLength: 0)
      } else {
        VStack(spacing: 0) {
          ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            recentRow(item)
            if index < items.count - 1 {
              Divider()
                .padding(.leading, 35)
            }
          }
        }
        Spacer(minLength: 0)
      }
    }
    .frame(maxHeight: .infinity, alignment: .top)
    .appCard(padding: 14)
  }

  private func recentRow(_ item: WellnessHistoryItem) -> some View {
    HStack(spacing: 10) {
      Image(systemName: item.activity.systemImage)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white)
        .frame(width: 25, height: 25)
        .background(AppTheme.accent, in: Circle())

      VStack(alignment: .leading, spacing: 2) {
        Text(item.activity.completionTitle)
          .font(.caption.weight(.semibold))
          .foregroundStyle(AppTheme.ink)
          .lineLimit(1)

        HStack(spacing: 5) {
          Text(item.detail)
            .lineLimit(1)
          Spacer(minLength: 2)
          Text(AppFormatters.relative.localizedString(for: item.completedAt, relativeTo: Date()))
            .lineLimit(1)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 6)
    .accessibilityElement(children: .combine)
  }

  private func todayCountText(for activity: WellnessActivityKind) -> String {
    let count = appModel.todayCount(for: activity)
    if activity == .neck {
      return "\(count)/\(appModel.settings.dailyWorkoutGoal) 次"
    }
    return "\(count) 次"
  }

  private var nextReminderText: String {
    if appModel.settings.isPaused { return "提醒已暂停至明天" }
    guard let due = appModel.nextDue else { return "提醒将在授权后开始" }
    let activity = appModel.reminderScheduler.nextActivity.localizedName
    return "下次 \(activity) · \(AppFormatters.time.string(from: due))"
  }
}
