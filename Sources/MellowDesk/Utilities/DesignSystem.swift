import SwiftUI

enum AppTheme {
  static let accent = Color(red: 0.18, green: 0.56, blue: 0.49)
  static let accentSoft = Color(red: 0.86, green: 0.95, blue: 0.92)
  static let ink = Color(red: 0.10, green: 0.16, blue: 0.18)
  static let secondaryInk = Color(red: 0.35, green: 0.42, blue: 0.44)
  static let warmBackground = Color(red: 0.97, green: 0.96, blue: 0.93)
  static let warning = Color(red: 0.86, green: 0.52, blue: 0.18)
  static let danger = Color(red: 0.76, green: 0.24, blue: 0.24)
}

struct CardModifier: ViewModifier {
  var padding: CGFloat = 18

  func body(content: Content) -> some View {
    content
      .padding(padding)
      .background(
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .fill(Color(nsColor: .controlBackgroundColor))
          .shadow(color: .black.opacity(0.06), radius: 12, y: 5)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .stroke(Color.primary.opacity(0.06), lineWidth: 1)
      )
  }
}

extension View {
  func appCard(padding: CGFloat = 18) -> some View {
    modifier(CardModifier(padding: padding))
  }
}

struct PillLabel: View {
  let systemImage: String
  let text: String
  var color: Color = AppTheme.accent

  var body: some View {
    Label(text, systemImage: systemImage)
      .font(.caption.weight(.semibold))
      .foregroundStyle(color)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(color.opacity(0.12), in: Capsule())
  }
}
