import SwiftUI

struct CompletionRing: View {
  let progress: Double
  let completed: Int
  let target: Int
  var size: CGFloat = 118

  var body: some View {
    ZStack {
      Circle()
        .stroke(AppTheme.accent.opacity(0.14), lineWidth: 10)
      Circle()
        .trim(from: 0, to: min(max(progress, 0), 1))
        .stroke(
          AppTheme.accent,
          style: StrokeStyle(lineWidth: 10, lineCap: .round)
        )
        .rotationEffect(.degrees(-90))
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: progress)
      VStack(spacing: 1) {
        Text("\(completed)")
          .font(.system(size: 32, weight: .bold, design: .rounded))
          .foregroundStyle(AppTheme.ink)
        Text("/ \(target) 次")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .frame(width: size, height: size)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("已完成 \(completed) 次，共 \(target) 次")
  }
}

struct StatTile: View {
  let title: String
  let value: String
  let caption: String
  let systemImage: String
  var tint: Color = AppTheme.accent

  var body: some View {
    HStack(alignment: .top, spacing: 13) {
      Image(systemName: systemImage)
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(tint)
        .frame(width: 38, height: 38)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))

      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(value)
          .font(.title3.weight(.bold))
          .foregroundStyle(AppTheme.ink)
        Text(caption)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer(minLength: 0)
    }
    .appCard(padding: 14)
  }
}

struct DailyCompletion: Identifiable, Equatable {
  let date: Date
  let count: Int
  var id: Date { date }
}

struct HistoryBarChart: View {
  let values: [DailyCompletion]
  let calendar: Calendar

  init(values: [DailyCompletion], calendar: Calendar = .current) {
    self.values = values
    self.calendar = calendar
  }

  var body: some View {
    GeometryReader { proxy in
      let maximum = max(values.map(\.count).max() ?? 1, 1)
      HStack(
        alignment: .bottom, spacing: max(5, proxy.size.width / CGFloat(max(values.count, 1)) * 0.24)
      ) {
        ForEach(values) { item in
          VStack(spacing: 6) {
            Text(item.count > 0 ? "\(item.count)" : "")
              .font(.caption2.monospacedDigit())
              .foregroundStyle(.secondary)
              .frame(height: 13)

            RoundedRectangle(cornerRadius: 5, style: .continuous)
              .fill(item.count > 0 ? AppTheme.accent : AppTheme.accent.opacity(0.10))
              .frame(
                maxWidth: .infinity,
                minHeight: 5,
                maxHeight: max(5, CGFloat(item.count) / CGFloat(maximum) * (proxy.size.height - 48))
              )

            Text(dayLabel(for: item.date))
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity)
        }
      }
    }
    .accessibilityElement(children: .contain)
  }

  private func dayLabel(for date: Date) -> String {
    if values.count <= 7 {
      let symbols = ["日", "一", "二", "三", "四", "五", "六"]
      return symbols[max(0, min(symbols.count - 1, calendar.component(.weekday, from: date) - 1))]
    }
    return "\(calendar.component(.day, from: date))"
  }
}
