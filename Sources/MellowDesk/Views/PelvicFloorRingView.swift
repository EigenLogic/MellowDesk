import MellowDeskCore
import SwiftUI

/// Twelve radial bars arranged as a clock face that contract toward the center
/// while lifting and return outward while relaxing.
///
/// All twelve move together, so the motion itself carries the cue: the ring closes
/// in on the core for 提 and opens back up for 放. A dashed guide marks the relaxed
/// position, which keeps the amount of contraction readable at a glance.
struct PelvicFloorRingView: View {
  let state: PelvicFloorRoutineState
  var diameter: CGFloat = 232

  private let barCount = 12
  private let barWidth: CGFloat = 8
  private let restCenterRadius: CGFloat = 94
  private let contractedCenterRadius: CGFloat = 52
  private let restBarLength: CGFloat = 34
  private let contractedBarLength: CGFloat = 27
  private let coreDiameter: CGFloat = 82

  var body: some View {
    ZStack {
      relaxedGuide
      core

      ForEach(0..<barCount, id: \.self) { index in
        bar(at: index)
      }

      center
    }
    .frame(width: diameter, height: diameter)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityDescription)
  }

  /// Eased so the squeeze gathers and settles instead of sliding at a constant rate.
  private var contraction: CGFloat {
    let progress = min(max(state.ringProgress, 0), 1)
    return CGFloat(progress * progress * (3 - 2 * progress))
  }

  private var centerRadius: CGFloat {
    restCenterRadius - (restCenterRadius - contractedCenterRadius) * contraction
  }

  private var barLength: CGFloat {
    restBarLength - (restBarLength - contractedBarLength) * contraction
  }

  private func bar(at index: Int) -> some View {
    Capsule(style: .continuous)
      .fill(AppTheme.accent.opacity(0.34 + 0.66 * Double(contraction)))
      .frame(width: barWidth, height: barLength)
      .shadow(color: AppTheme.accent.opacity(0.26 * Double(contraction)), radius: 5)
      .offset(y: -centerRadius)
      .rotationEffect(.degrees(Double(index) / Double(barCount) * 360))
  }

  /// The outer edge the bars rest against when nothing is engaged.
  private var relaxedGuide: some View {
    let guideDiameter = (restCenterRadius + restBarLength / 2) * 2

    return Circle()
      .strokeBorder(
        AppTheme.accent.opacity(0.16),
        style: StrokeStyle(lineWidth: 1, dash: [2, 5])
      )
      .frame(width: guideDiameter, height: guideDiameter)
  }

  private var core: some View {
    Circle()
      .fill(AppTheme.accentSoft.opacity(0.45 + 0.3 * Double(contraction)))
      .frame(width: coreDiameter, height: coreDiameter)
  }

  private var center: some View {
    VStack(spacing: 1) {
      Text(state.isFinished ? "✓" : state.phase.glyph)
        .font(.system(size: 40, weight: .bold, design: .rounded))
        .foregroundStyle(AppTheme.accent)
      Text(state.isFinished ? "练完啦" : state.phase.localizedName)
        .font(.caption.weight(.semibold))
        .foregroundStyle(AppTheme.ink)
    }
  }

  private var accessibilityDescription: String {
    if state.isFinished {
      return "提肛跟练结束，共完成 \(state.completedLifts) 次"
    }
    return "\(state.segment.title)，\(state.phase.localizedName)，已完成 \(state.completedLifts) 次"
  }
}
