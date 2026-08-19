import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    ProcessInfo.processInfo.disableAutomaticTermination(
      "MellowDesk keeps scheduled wellness reminders active."
    )
    AppWindowCoordinator.shared.installStatusItem()
    AppModel.shared.start()
    observeScheduleChanges()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  func applicationDidBecomeActive(_ notification: Notification) {
    AppModel.shared.applicationDidBecomeActive()
    AppWindowCoordinator.shared.applicationDidBecomeActive()
  }

  func applicationDidResignActive(_ notification: Notification) {
    AppWindowCoordinator.shared.applicationDidResignActive()
  }

  func applicationDidHide(_ notification: Notification) {
    AppWindowCoordinator.shared.applicationDidHide()
  }

  func applicationDidUnhide(_ notification: Notification) {
    AppWindowCoordinator.shared.applicationDidBecomeActive()
  }

  func applicationWillTerminate(_ notification: Notification) {
    for observer in observers {
      observer.center.removeObserver(observer.token)
    }
    observers.removeAll()
    AppModel.shared.reminderScheduler.shutdown()
  }

  private func observeScheduleChanges() {
    let workspaceCenter = NSWorkspace.shared.notificationCenter
    let wakeToken = workspaceCenter.addObserver(
      forName: NSWorkspace.didWakeNotification,
      object: nil,
      queue: .main
    ) { _ in
      Task { @MainActor in AppModel.shared.applicationDidBecomeActive() }
    }
    observers.append((workspaceCenter, wakeToken))

    let defaultCenter = NotificationCenter.default
    let scheduleChangeNames = [
      Notification.Name("NSSystemClockDidChangeNotification"),
      Notification.Name("NSSystemTimeZoneDidChangeNotification"),
      Notification.Name("NSCalendarDayChangedNotification"),
    ]
    for name in scheduleChangeNames {
      let token = defaultCenter.addObserver(
        forName: name,
        object: nil,
        queue: .main
      ) { _ in
        Task { @MainActor in AppModel.shared.applicationDidBecomeActive() }
      }
      observers.append((defaultCenter, token))
    }

    let screenToken = defaultCenter.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { _ in
      Task { @MainActor in
        AppWindowCoordinator.shared.applicationDidChangeScreenParameters()
      }
    }
    observers.append((defaultCenter, screenToken))
  }
}
