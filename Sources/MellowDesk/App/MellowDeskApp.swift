import SwiftUI

@MainActor
@main
struct MellowDeskApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var appModel = AppModel.shared

  var body: some Scene {
    MenuBarExtra {
      MenuBarContentView()
        .environmentObject(appModel)
    } label: {
      Label("小桌伴", systemImage: "leaf.fill")
    }
    .menuBarExtraStyle(.window)
  }
}
