import SwiftUI

struct UpdateReadyView: View {
  let version: String
  let onInstall: () -> Void
  let onLater: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(alignment: .top, spacing: 14) {
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 38))
          .foregroundStyle(AppTheme.accent)

        VStack(alignment: .leading, spacing: 7) {
          Text("新版本已准备好")
            .font(.title2.bold())
            .foregroundStyle(AppTheme.ink)
          Text("小桌伴 \(version) 已在后台下载，并通过完整性与签名验证。")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          Text("现在安装会退出并重新打开小桌伴；选择稍后时，会在下次退出应用时自动安装。")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      Spacer(minLength: 0)

      HStack {
        Spacer()
        Button("稍后", action: onLater)
          .keyboardShortcut(.cancelAction)
        Button("安装并重启", action: onInstall)
          .buttonStyle(.borderedProminent)
          .tint(AppTheme.accent)
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding(26)
    .frame(width: 500, height: 240)
    .background(AppTheme.warmBackground.opacity(0.55))
  }
}
