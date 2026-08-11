import AppKit
import OSLog
import SwiftUI

@MainActor
final class AppWindowCoordinator: NSObject {
  static let shared = AppWindowCoordinator()

  private var dashboardWindow: NSWindow?
  private var settingsWindow: NSWindow?
  private var workoutWindow: NSWindow?
  private var workoutViewModel: WorkoutViewModel?
  private var workoutCloseObserver: WindowCloseObserver?
  private var pendingInitialCameraAuthorizationWindow: NSWindow?
  private var initialCameraAuthorizationRestoreExpiry: DispatchWorkItem?
  private let logger = Logger(
    subsystem: "cn.eigenlogic.mellowdesk",
    category: "camera-focus"
  )

  func showDashboard() {
    if let dashboardWindow {
      present(dashboardWindow)
      return
    }

    let view = DashboardView()
      .environmentObject(AppModel.shared)
    let window = makeWindow(
      title: "小桌伴",
      size: NSSize(width: 840, height: 650),
      minimumSize: NSSize(width: 720, height: 560),
      rootView: view
    )
    dashboardWindow = window
    present(window)
  }

  func showSettings() {
    if let settingsWindow {
      present(settingsWindow)
      return
    }

    let view = SettingsView()
      .environmentObject(AppModel.shared)
    let window = makeWindow(
      title: "设置",
      size: NSSize(width: 610, height: 650),
      minimumSize: NSSize(width: 560, height: 580),
      rootView: view
    )
    settingsWindow = window
    present(window)
  }

  func showWorkout() {
    if let workoutWindow {
      present(workoutWindow)
      return
    }

    let viewModel = WorkoutViewModel(
      appModel: AppModel.shared,
      initialCameraAuthorizationDidResolve: { [weak self] in
        self?.restoreWorkoutWindowAfterInitialCameraAuthorization()
      }
    )
    let view = WorkoutView(viewModel: viewModel)
      .environmentObject(AppModel.shared)
    let window = makeWindow(
      title: "颈部微运动",
      size: NSSize(width: 1000, height: 700),
      minimumSize: NSSize(width: 860, height: 620),
      rootView: view
    )

    let observer = WindowCloseObserver(
      onClose: { [weak self, weak viewModel] in
        viewModel?.windowDidClose()
        self?.clearInitialCameraAuthorizationRestore()
        self?.workoutWindow = nil
        self?.workoutViewModel = nil
        self?.workoutCloseObserver = nil
      },
      onMiniaturize: { [weak self, weak viewModel] in
        self?.clearInitialCameraAuthorizationRestore()
        viewModel?.workoutWindowDidBecomeHidden()
      },
      onDeminiaturize: { [weak viewModel] in
        viewModel?.workoutWindowDidBecomeVisible()
      }
    )
    window.delegate = observer
    workoutCloseObserver = observer
    workoutViewModel = viewModel
    workoutWindow = window
    present(window)
  }

  func closeWorkout() {
    workoutWindow?.close()
  }

  func applicationDidBecomeActive() {
    guard let workoutWindow, workoutWindow.isVisible, !workoutWindow.isMiniaturized else { return }
    workoutViewModel?.workoutWindowDidBecomeVisible()
    scheduleInitialCameraAuthorizationRestoreIfNeeded()
  }

  func applicationDidHide() {
    clearInitialCameraAuthorizationRestore()
    workoutViewModel?.workoutWindowDidBecomeHidden()
  }

  private func restoreWorkoutWindowAfterInitialCameraAuthorization() {
    guard let workoutWindow,
      workoutViewModel?.canRestoreAfterInitialCameraAuthorization == true,
      workoutWindow.isVisible,
      !workoutWindow.isMiniaturized,
      !NSApp.isHidden
    else { return }

    clearInitialCameraAuthorizationRestore()
    pendingInitialCameraAuthorizationWindow = workoutWindow
    logger.notice("Camera authorization resolved; waiting for application activation")

    let expiry = DispatchWorkItem { [weak self, weak workoutWindow] in
      guard let self,
        let workoutWindow,
        self.pendingInitialCameraAuthorizationWindow === workoutWindow
      else { return }
      self.logger.notice("Camera authorization focus restore expired")
      self.clearInitialCameraAuthorizationRestore()
    }
    initialCameraAuthorizationRestoreExpiry = expiry
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: expiry)

    requestApplicationActivation()
    if NSApp.isActive {
      scheduleInitialCameraAuthorizationRestoreIfNeeded()
    }
  }

  private func scheduleInitialCameraAuthorizationRestoreIfNeeded() {
    guard pendingInitialCameraAuthorizationWindow != nil else { return }
    DispatchQueue.main.async { [weak self] in
      self?.finishInitialCameraAuthorizationRestoreIfPossible()
    }
  }

  private func finishInitialCameraAuthorizationRestoreIfPossible() {
    guard let pendingWindow = pendingInitialCameraAuthorizationWindow,
      pendingWindow === workoutWindow,
      workoutViewModel?.canRestoreAfterInitialCameraAuthorization == true,
      pendingWindow.isVisible,
      !pendingWindow.isMiniaturized,
      !NSApp.isHidden
    else {
      clearInitialCameraAuthorizationRestore()
      return
    }

    guard NSApp.isActive else {
      requestApplicationActivation()
      return
    }

    pendingWindow.makeKeyAndOrderFront(nil)
    logger.notice("Workout window restored after camera authorization")
    clearInitialCameraAuthorizationRestore()
  }

  private func requestApplicationActivation() {
    if #available(macOS 14.0, *) {
      NSApp.activate()
    } else {
      NSApp.activate(ignoringOtherApps: true)
    }
  }

  private func clearInitialCameraAuthorizationRestore() {
    pendingInitialCameraAuthorizationWindow = nil
    initialCameraAuthorizationRestoreExpiry?.cancel()
    initialCameraAuthorizationRestoreExpiry = nil
  }

  private func makeWindow<Content: View>(
    title: String,
    size: NSSize,
    minimumSize: NSSize,
    rootView: Content
  ) -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    window.title = title
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.isReleasedWhenClosed = false
    window.minSize = minimumSize
    window.center()
    window.contentViewController = NSHostingController(rootView: rootView)
    return window
  }

  private func present(_ window: NSWindow) {
    NSApp.activate(ignoringOtherApps: true)
    if window.isMiniaturized {
      window.deminiaturize(nil)
    }
    window.makeKeyAndOrderFront(nil)
  }
}

private final class WindowCloseObserver: NSObject, NSWindowDelegate {
  private let onClose: () -> Void
  private let onMiniaturize: () -> Void
  private let onDeminiaturize: () -> Void

  init(
    onClose: @escaping () -> Void,
    onMiniaturize: @escaping () -> Void,
    onDeminiaturize: @escaping () -> Void
  ) {
    self.onClose = onClose
    self.onMiniaturize = onMiniaturize
    self.onDeminiaturize = onDeminiaturize
  }

  func windowWillClose(_ notification: Notification) {
    onClose()
  }

  func windowDidMiniaturize(_ notification: Notification) {
    onMiniaturize()
  }

  func windowDidDeminiaturize(_ notification: Notification) {
    onDeminiaturize()
  }
}
