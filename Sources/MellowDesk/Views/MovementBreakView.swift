import Foundation
import SwiftUI

struct MovementBreakView: View {
  let includesWater: Bool
  let onComplete: () -> Void
  let onCancel: () -> Void

  @State private var startedAt = Date()
  @State private var isResolving = false

  private let duration: TimeInterval = 2 * 60

  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      header

      TimelineView(.periodic(from: startedAt, by: 1)) { context in
        VStack(alignment: .leading, spacing: 20) {
          timer(at: context.date)
          movementSteps(at: context.date)
        }
      }

      Spacer(minLength: 0)
      actions
    }
    .padding(30)
    .frame(minWidth: 560, minHeight: 480)
    .background(AppTheme.warmBackground.opacity(0.55))
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 15) {
      Image(systemName: includesWater ? "drop.fill" : "figure.walk")
        .font(.system(size: 23, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 48, height: 48)
        .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 14))

      VStack(alignment: .leading, spacing: 5) {
        Text(includesWater ? "喝口水，再起来动动" : "起来动动吧")
          .font(.system(size: 25, weight: .bold, design: .rounded))
          .foregroundStyle(AppTheme.ink)
        Text("离开椅子两分钟，动作保持轻松舒适。")
          .font(.subheadline)
          .foregroundStyle(AppTheme.secondaryInk)
      }
    }
  }

  private func timer(at date: Date) -> some View {
    let elapsed = elapsedSeconds(at: date)
    let remaining = max(0, Int((duration - elapsed).rounded(.up)))

    return VStack(alignment: .leading, spacing: 9) {
      HStack(alignment: .firstTextBaseline) {
        Text(remaining == 0 ? "完成啦" : formattedTime(remaining))
          .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
          .foregroundStyle(AppTheme.ink)
        Spacer()
        Text(remaining == 0 ? "感觉舒服就好" : "建议活动 2 分钟")
          .font(.caption.weight(.semibold))
          .foregroundStyle(AppTheme.accent)
      }

      ProgressView(value: min(elapsed, duration), total: duration)
        .tint(AppTheme.accent)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(remaining == 0 ? "两分钟活动结束" : "活动还剩 \(remaining) 秒")
  }

  private func movementSteps(at date: Date) -> some View {
    let activeStep = activeStepIndex(at: date)

    return VStack(alignment: .leading, spacing: 10) {
      movementStep(
        index: 0,
        activeStep: activeStep,
        systemImage: includesWater ? "drop" : "figure.stand",
        title: includesWater ? "先喝几口水" : "起身站稳",
        detail: includesWater ? "按自己的节奏喝，不必一次喝完。" : "双脚踩稳地面，肩膀自然放松。"
      )
      movementStep(
        index: 1,
        activeStep: activeStep,
        systemImage: "figure.walk",
        title: "慢慢走一走",
        detail: "在桌边走动，或者舒适地原地踏步。"
      )
      movementStep(
        index: 2,
        activeStep: activeStep,
        systemImage: "figure.flexibility",
        title: "舒展肩背和双腿",
        detail: "轻轻伸展，不憋气，也不追求幅度。"
      )
    }
  }

  private func movementStep(
    index: Int,
    activeStep: Int,
    systemImage: String,
    title: String,
    detail: String
  ) -> some View {
    let isActive = index == activeStep

    return HStack(spacing: 13) {
      Image(systemName: systemImage)
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(isActive ? .white : AppTheme.accent)
        .frame(width: 36, height: 36)
        .background(
          isActive ? AppTheme.accent : AppTheme.accent.opacity(0.12),
          in: RoundedRectangle(cornerRadius: 10)
        )

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(AppTheme.ink)
        Text(detail)
          .font(.caption)
          .foregroundStyle(AppTheme.secondaryInk)
      }
      Spacer(minLength: 0)
    }
    .padding(12)
    .background(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(
          isActive
            ? AppTheme.accentSoft.opacity(0.75)
            : Color(nsColor: .controlBackgroundColor)
        )
    )
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(
          isActive ? AppTheme.accent.opacity(0.22) : Color.primary.opacity(0.05),
          lineWidth: 1
        )
    )
  }

  private var actions: some View {
    HStack(spacing: 10) {
      Button("稍后再说") {
        resolve(onCancel)
      }
      .keyboardShortcut(.cancelAction)

      Spacer()

      Button {
        resolve(onComplete)
      } label: {
        Label("我完成了", systemImage: "checkmark")
          .frame(minWidth: 118)
      }
      .buttonStyle(.borderedProminent)
      .tint(AppTheme.accent)
      .controlSize(.large)
      .keyboardShortcut(.defaultAction)
    }
    .disabled(isResolving)
  }

  private func elapsedSeconds(at date: Date) -> TimeInterval {
    min(max(0, date.timeIntervalSince(startedAt)), duration)
  }

  private func activeStepIndex(at date: Date) -> Int {
    let progress = elapsedSeconds(at: date) / duration
    if progress < 0.2 { return 0 }
    if progress < 0.65 { return 1 }
    return 2
  }

  private func formattedTime(_ seconds: Int) -> String {
    String(format: "%d:%02d", seconds / 60, seconds % 60)
  }

  private func resolve(_ action: () -> Void) {
    guard !isResolving else { return }
    isResolving = true
    action()
  }
}
