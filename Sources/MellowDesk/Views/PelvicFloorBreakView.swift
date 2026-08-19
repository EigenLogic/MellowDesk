import Foundation
import MellowDeskCore
import SwiftUI

/// The two-minute pelvic-floor follow-along.
///
/// The clock is derived from `runningSince` plus the time banked in `accumulated`,
/// so pausing never drifts. Nothing is measured; completing the routine records one session.
struct PelvicFloorBreakView: View {
  var routine: PelvicFloorRoutine = .v1
  let onComplete: () -> Void
  let onSkip: () -> Void

  @State private var accumulated: TimeInterval = 0
  @State private var runningSince: Date? = Date()
  @State private var didFinish = false

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      header

      TimelineView(
        .animation(minimumInterval: 1.0 / 30.0, paused: runningSince == nil)
      ) { context in
        let state = routine.state(at: elapsed(at: context.date))

        VStack(spacing: 15) {
          PelvicFloorRingView(state: state)

          Text(state.isFinished ? "四段节奏都练完了，放松一下。" : state.segment.coaching)
            .font(.subheadline)
            .foregroundStyle(AppTheme.secondaryInk)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(height: 38, alignment: .top)

          segmentTrack(state)
          timer(state)
        }
        .frame(maxWidth: .infinity)
      }

      Spacer(minLength: 0)

      Text(routine.safetyNotice)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      actions
    }
    .padding(26)
    .frame(minWidth: 520, minHeight: 640)
    .background(AppTheme.warmBackground.opacity(0.55))
    .task(id: runningSince) {
      await runUntilFinished()
    }
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 14) {
      // The same twelve-bar ring the follow-along animates.
      Image(systemName: "slowmo")
        .font(.system(size: 26, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 48, height: 48)
        .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 14))

      VStack(alignment: .leading, spacing: 5) {
        Text("\(routine.displayName) 2 分钟")
          .font(.system(size: 25, weight: .bold, design: .rounded))
          .foregroundStyle(AppTheme.ink)
        Text("坐着或站着都行：12 根竖线向圆心收缩时收提，还原时放松；练完会记入完成记录。")
          .font(.subheadline)
          .foregroundStyle(AppTheme.secondaryInk)
      }
    }
  }

  private func segmentTrack(_ state: PelvicFloorRoutineState) -> some View {
    HStack(spacing: 8) {
      ForEach(Array(routine.segments.enumerated()), id: \.element.id) { index, segment in
        segmentChip(index: index, segment: segment, state: state)
      }
    }
  }

  private func segmentChip(
    index: Int,
    segment: PelvicFloorSegment,
    state: PelvicFloorRoutineState
  ) -> some View {
    let isCurrent = !state.isFinished && index == state.segmentIndex
    let fill: Double =
      state.isFinished || index < state.segmentIndex
      ? 1
      : (isCurrent ? state.segmentProgress : 0)

    return VStack(spacing: 6) {
      Text(segment.title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(isCurrent ? AppTheme.accent : AppTheme.secondaryInk)
        .lineLimit(1)

      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule().fill(AppTheme.accent.opacity(0.14))
          Capsule()
            .fill(AppTheme.accent.opacity(isCurrent ? 1 : 0.5))
            .frame(width: proxy.size.width * fill)
        }
      }
      .frame(height: 4)
    }
    .padding(.vertical, 9)
    .padding(.horizontal, 10)
    .frame(maxWidth: .infinity)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(
          isCurrent
            ? AppTheme.accentSoft.opacity(0.75)
            : Color(nsColor: .controlBackgroundColor)
        )
    )
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(
          isCurrent ? AppTheme.accent.opacity(0.22) : Color.primary.opacity(0.05),
          lineWidth: 1
        )
    )
  }

  private func timer(_ state: PelvicFloorRoutineState) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        Text(
          state.isFinished
            ? "完成啦"
            : formattedTime(Int(state.totalRemaining.rounded(.up)))
        )
        .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
        .foregroundStyle(AppTheme.ink)

        Spacer()

        VStack(alignment: .trailing, spacing: 2) {
          Text(state.isFinished ? "四段都练完了" : state.segment.tempo)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.accent)
          Text("已完成 \(state.completedLifts) 次")
            .font(.caption2)
            .foregroundStyle(AppTheme.secondaryInk)
            .monospacedDigit()
        }
      }

      ProgressView(value: state.elapsed, total: routine.totalDuration)
        .tint(AppTheme.accent)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      state.isFinished
        ? "提肛跟练完成"
        : "还剩 \(Int(state.totalRemaining.rounded(.up))) 秒"
    )
  }

  private var actions: some View {
    HStack(spacing: 10) {
      if didFinish {
        Button("再来一组") {
          restart()
        }
      } else {
        Button(runningSince == nil ? "继续" : "暂停") {
          togglePause()
        }
      }

      Spacer()

      Button {
        if didFinish {
          onComplete()
        } else {
          onSkip()
        }
      } label: {
        Label(
          didFinish ? "完成" : "跳过本次",
          systemImage: didFinish ? "checkmark" : "forward.end"
        )
        .frame(minWidth: 112)
      }
      .buttonStyle(.borderedProminent)
      .tint(AppTheme.accent)
      .controlSize(.large)
      .keyboardShortcut(.defaultAction)
    }
  }

  private func elapsed(at date: Date) -> TimeInterval {
    guard let runningSince else { return accumulated }
    let running = max(0, date.timeIntervalSince(runningSince))
    return min(accumulated + running, routine.totalDuration)
  }

  /// Sleeps out the remaining time so the finished frame stops the timeline
  /// instead of redrawing a static ring thirty times a second.
  private func runUntilFinished() async {
    guard let startedAt = runningSince else { return }
    let remaining = routine.totalDuration - accumulated
    guard remaining > 0 else { return }

    try? await Task.sleep(for: .seconds(remaining))
    guard !Task.isCancelled, runningSince == startedAt else { return }

    accumulated = routine.totalDuration
    runningSince = nil
    didFinish = true
  }

  private func togglePause() {
    if let runningSince {
      accumulated = min(
        accumulated + max(0, Date().timeIntervalSince(runningSince)),
        routine.totalDuration
      )
      self.runningSince = nil
    } else if accumulated < routine.totalDuration {
      runningSince = Date()
    }
  }

  private func restart() {
    accumulated = 0
    didFinish = false
    runningSince = Date()
  }

  private func formattedTime(_ seconds: Int) -> String {
    String(format: "%d:%02d", seconds / 60, seconds % 60)
  }
}
