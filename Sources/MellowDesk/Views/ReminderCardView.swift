import SwiftUI

struct StatusReminderView: View {
  var body: some View {
    ZStack(alignment: .topTrailing) {
      ReminderCardView()
        .padding(.top, 8)

      ReminderPointer()
        .fill(AppTheme.warmBackground)
        .frame(width: 16, height: 9)
        .padding(.trailing, 26)
    }
    .frame(width: 390, height: 198, alignment: .bottom)
  }
}

private struct ReminderPointer: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.midX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
    path.closeSubpath()
    return path
  }
}

struct ReminderCardView: View {
  @EnvironmentObject private var appModel: AppModel
  @State private var isResolving = false

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: "leaf.fill")
          .font(.system(size: 20, weight: .semibold))
          .foregroundStyle(.white)
          .frame(width: 42, height: 42)
          .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 12))

        VStack(alignment: .leading, spacing: 3) {
          Text("该活动一下颈肩了")
            .font(.headline)
            .foregroundStyle(AppTheme.ink)
          Text("用 3 分钟跟着动画活动一下。选择操作前，这张提醒会一直留在这里。")
            .font(.caption)
            .foregroundStyle(AppTheme.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      Button {
        guard !isResolving else { return }
        guard let reminderID = appModel.activeReminder?.id else { return }
        isResolving = true
        if !appModel.startCurrentReminder(id: reminderID) {
          isResolving = false
        }
      } label: {
        Label("开始 3 分钟微运动", systemImage: "play.fill")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .tint(AppTheme.accent)
      .controlSize(.large)

      HStack(spacing: 10) {
        Button("推迟 10 分钟") {
          guard !isResolving else { return }
          isResolving = true
          appModel.snoozeTenMinutes()
        }
        .frame(maxWidth: .infinity)

        Button("今天暂停") {
          guard !isResolving else { return }
          isResolving = true
          appModel.pauseUntilTomorrow()
        }
        .frame(maxWidth: .infinity)
      }
      .disabled(isResolving)
    }
    .padding(18)
    .frame(width: 390, height: 190)
    .background(
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .fill(AppTheme.warmBackground)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
    )
  }
}
