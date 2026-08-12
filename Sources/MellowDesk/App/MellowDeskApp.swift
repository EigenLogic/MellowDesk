import SwiftUI

@MainActor
@main
struct MellowDeskApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var appModel = AppModel.shared

  var body: some Scene {
    Settings {
      EmptyView()
        .environmentObject(appModel)
    }
  }
}
