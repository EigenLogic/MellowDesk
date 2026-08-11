import SwiftUI

enum ExerciseAnimationKind: String, CaseIterable {
  case rotation
  case lateralTilt
  case nod
}

struct ExerciseAnimationView: View {
  let kind: ExerciseAnimationKind
  var isPlaying = true
  var directionSign: Double? = nil

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { context in
      let progress = motionProgress(at: context.date)
      ZStack {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
          .fill(
            LinearGradient(
              colors: [AppTheme.accentSoft, Color.white.opacity(0.92)],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )

        MotionFigure(kind: kind, progress: progress, directionSign: directionSign)
          .padding(22)

        VStack {
          Spacer()
          motionHint(progress: progress)
            .padding(.bottom, 14)
        }
      }
    }
    .aspectRatio(1.34, contentMode: .fit)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityDescription)
  }

  private func motionProgress(at date: Date) -> Double {
    let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4.0) / 4.0
    switch phase {
    case 0..<0.16:
      return 0
    case 0.16..<0.42:
      return ease((phase - 0.16) / 0.26)
    case 0.42..<0.58:
      return 1
    case 0.58..<0.84:
      return 1 - ease((phase - 0.58) / 0.26)
    default:
      return 0
    }
  }

  private func ease(_ value: Double) -> Double {
    value * value * (3 - 2 * value)
  }

  @ViewBuilder
  private func motionHint(progress: Double) -> some View {
    let outbound = progress > 0.12
    HStack(spacing: 7) {
      Image(systemName: hintIcon)
      Text(outbound ? targetHint : "回到中立位")
    }
    .font(.caption.weight(.semibold))
    .foregroundStyle(AppTheme.secondaryInk)
    .padding(.horizontal, 12)
    .padding(.vertical, 7)
    .background(.ultraThinMaterial, in: Capsule())
  }

  private var hintIcon: String {
    switch kind {
    case .rotation: return "arrow.left.and.right"
    case .lateralTilt: return "arrow.up.left.and.arrow.down.right"
    case .nod: return "arrow.up.and.down"
    }
  }

  private var targetHint: String {
    switch kind {
    case .rotation: return "缓慢转向舒适范围"
    case .lateralTilt: return "耳朵靠近肩膀方向"
    case .nod: return "下巴轻轻向胸前"
    }
  }

  private var accessibilityDescription: String {
    switch kind {
    case .rotation: return "动画演示缓慢左右转头并回到中立位"
    case .lateralTilt: return "动画演示头部向左右侧倾并回到中立位"
    case .nod: return "动画演示轻柔低头并回到中立位"
    }
  }
}

private struct MotionFigure: View {
  let kind: ExerciseAnimationKind
  let progress: Double
  let directionSign: Double?

  var body: some View {
    GeometryReader { proxy in
      let size = min(proxy.size.width, proxy.size.height)
      let direction =
        directionSign
        ?? (sin(Date().timeIntervalSinceReferenceDate / 4.0 * .pi) >= 0 ? 1.0 : -1.0)
      let signed = direction * progress

      ZStack {
        ShoulderShape()
          .fill(AppTheme.accent.opacity(0.82))
          .frame(width: size * 0.70, height: size * 0.30)
          .offset(y: size * 0.27)

        Capsule()
          .fill(Color(red: 0.84, green: 0.68, blue: 0.57))
          .frame(width: size * 0.14, height: size * 0.20)
          .offset(y: size * 0.10)

        HeadView(turn: kind == .rotation ? signed : 0)
          .frame(width: size * 0.34, height: size * 0.42)
          .rotationEffect(
            .degrees(kind == .lateralTilt ? signed * 17 : kind == .nod ? signed * 7 : 0),
            anchor: .bottom
          )
          .offset(
            x: kind == .lateralTilt ? signed * size * 0.035 : 0,
            y: kind == .nod ? signed * size * 0.045 : -size * 0.09
          )

        motionArrow(size: size, signed: signed)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  @ViewBuilder
  private func motionArrow(size: CGFloat, signed: Double) -> some View {
    switch kind {
    case .rotation:
      Image(systemName: signed >= 0 ? "arrow.turn.up.right" : "arrow.turn.up.left")
        .font(.system(size: size * 0.11, weight: .semibold))
        .foregroundStyle(AppTheme.accent)
        .offset(x: signed >= 0 ? size * 0.31 : -size * 0.31, y: -size * 0.12)
    case .lateralTilt:
      Image(systemName: signed >= 0 ? "arrow.down.right" : "arrow.down.left")
        .font(.system(size: size * 0.10, weight: .semibold))
        .foregroundStyle(AppTheme.accent)
        .offset(x: signed >= 0 ? size * 0.29 : -size * 0.29, y: -size * 0.13)
    case .nod:
      Image(systemName: "arrow.down")
        .font(.system(size: size * 0.10, weight: .semibold))
        .foregroundStyle(AppTheme.accent)
        .offset(x: size * 0.28, y: -size * 0.04)
    }
  }
}

private struct HeadView: View {
  let turn: Double

  var body: some View {
    GeometryReader { proxy in
      let width = proxy.size.width
      let horizontalScale = max(0.72, 1 - abs(turn) * 0.22)
      ZStack {
        Ellipse()
          .fill(Color(red: 0.91, green: 0.76, blue: 0.64))
          .overlay(
            Ellipse()
              .stroke(Color.black.opacity(0.09), lineWidth: 1)
          )

        HStack(spacing: width * 0.17) {
          Circle().fill(AppTheme.ink).frame(width: 5, height: 5)
          Circle().fill(AppTheme.ink).frame(width: 5, height: 5)
        }
        .opacity(max(0.25, 1 - abs(turn) * 0.65))
        .offset(x: turn * width * 0.08, y: -8)

        Capsule()
          .fill(AppTheme.ink.opacity(0.52))
          .frame(width: 3, height: 13)
          .offset(x: turn * width * 0.17, y: 4)

        Capsule()
          .fill(AppTheme.ink.opacity(0.46))
          .frame(width: width * 0.19, height: 3)
          .offset(x: turn * width * 0.08, y: 20)
      }
      .scaleEffect(x: horizontalScale, y: 1)
    }
  }
}

private struct ShoulderShape: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.midX, y: 0))
    path.addCurve(
      to: CGPoint(x: rect.maxX, y: rect.height * 0.58),
      control1: CGPoint(x: rect.width * 0.72, y: 0),
      control2: CGPoint(x: rect.width * 0.94, y: rect.height * 0.22)
    )
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    path.addLine(to: CGPoint(x: 0, y: rect.maxY))
    path.addLine(to: CGPoint(x: 0, y: rect.height * 0.58))
    path.addCurve(
      to: CGPoint(x: rect.midX, y: 0),
      control1: CGPoint(x: rect.width * 0.06, y: rect.height * 0.22),
      control2: CGPoint(x: rect.width * 0.28, y: 0)
    )
    path.closeSubpath()
    return path
  }
}
