import AppKit
import MellowDeskCore
import OSLog
import SwiftUI

struct ReminderContentIdentity {
  private(set) var renderedReminderID: ReminderOccurrence.ID?

  mutating func shouldRender(_ reminderID: ReminderOccurrence.ID) -> Bool {
    guard renderedReminderID != reminderID else { return false }
    renderedReminderID = reminderID
    return true
  }
}

@MainActor
final class AppWindowCoordinator: NSObject, NSPopoverDelegate {
  static let shared = AppWindowCoordinator()

  private enum StatusPopoverMode: Equatable {
    case menu
  }

  private var dashboardWindow: NSWindow?
  private var settingsWindow: NSWindow?
  private var workoutWindow: NSWindow?
  private var workoutViewModel: WorkoutViewModel?
  private var workoutCloseObserver: WindowCloseObserver?
  private var movementBreakWindow: NSWindow?
  private var movementBreakCloseObserver: WindowCloseObserver?
  private var movementBreakSessionID: UUID?
  private var movementBreakDidResolve = false
  private var statusItem: NSStatusItem?
  private var statusPopover: NSPopover?
  private var statusPopoverMode: StatusPopoverMode?
  private var reminderPanel: NSPanel?
  private var reminderContentIdentity = ReminderContentIdentity()
  private var desiredReminder: ReminderOccurrence?
  private var lastAudibleReminderID: String?
  private var reminderWorkoutRestore: DispatchWorkItem?
  private weak var pendingReminderWorkoutWindow: NSWindow?
  private var reminderMovementBreakRestore: DispatchWorkItem?
  private weak var pendingReminderMovementBreakWindow: NSWindow?
  private var pendingInitialCameraAuthorizationWindow: NSWindow?
  private var initialCameraAuthorizationRestoreFallback: DispatchWorkItem?
  private let logger = Logger(
    subsystem: "cn.eigenlogic.mellowdesk",
    category: "camera-focus"
  )
  private let reminderLogger = Logger(
    subsystem: "cn.eigenlogic.mellowdesk",
    category: "status-reminder"
  )

  func installStatusItem() {
    guard statusItem == nil else { return }

    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    if let button = item.button {
      let image = NSImage(
        systemSymbolName: "leaf.fill",
        accessibilityDescription: "小桌伴"
      )
      image?.isTemplate = true
      button.image = image
      button.toolTip = "小桌伴"
      button.target = self
      button.action = #selector(statusItemClicked(_:))
    }
    statusItem = item

    let popover = NSPopover()
    popover.animates = true
    popover.delegate = self
    statusPopover = popover

    if let desiredReminder {
      showReminderPanel(desiredReminder)
    }
  }

  func showDashboard() {
    dismissStatusMenu()
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
    dismissStatusMenu()
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
    dismissStatusMenu()
    if let workoutWindow {
      if workoutViewModel?.phase == .completed {
        workoutWindow.close()
      } else {
        present(workoutWindow)
        return
      }
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
        self?.reminderWorkoutRestore?.cancel()
        self?.reminderWorkoutRestore = nil
        self?.pendingReminderWorkoutWindow = nil
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

  /// A click inside a nonactivating reminder panel does not automatically activate
  /// this accessory app. End the panel's mouse event first, then create and force-front
  /// the explicitly requested workout before retrying normal key-window activation.
  func showWorkoutFromReminder() {
    reminderWorkoutRestore?.cancel()
    let present = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.showWorkout()
      guard let workoutWindow = self.workoutWindow else { return }

      self.pendingReminderWorkoutWindow = workoutWindow
      workoutWindow.orderFrontRegardless()
      self.requestApplicationActivation()
      self.reminderLogger.notice(
        "Reminder workout force-fronted; appActive=\(NSApp.isActive, privacy: .public)"
      )
      let fallback = DispatchWorkItem { [weak self, weak workoutWindow] in
        guard let self, let workoutWindow, workoutWindow === self.workoutWindow else { return }
        if NSApp.isActive {
          workoutWindow.makeKeyAndOrderFront(nil)
        } else {
          workoutWindow.orderFrontRegardless()
        }
        self.pendingReminderWorkoutWindow = nil
        self.reminderWorkoutRestore = nil
      }
      self.reminderWorkoutRestore = fallback
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: fallback)
    }
    reminderWorkoutRestore = present
    DispatchQueue.main.async(execute: present)
  }

  /// Reminder panels do not activate this menu-bar app. Let the panel's click finish,
  /// then create the requested break window and explicitly restore it to the front.
  func showMovementBreakFromReminder(_ occurrence: ReminderOccurrence) {
    guard occurrence.activity.isQuickActivity else { return }
    reminderMovementBreakRestore?.cancel()

    let show = DispatchWorkItem { [weak self] in
      guard let self else { return }
      let window = self.prepareMovementBreakWindow(
        activity: occurrence.activity,
        sourceID: occurrence.id,
        fromReminder: true
      )

      self.pendingReminderMovementBreakWindow = window
      window.orderFrontRegardless()
      self.requestApplicationActivation()
      self.reminderLogger.notice(
        "Reminder movement break force-fronted; appActive=\(NSApp.isActive, privacy: .public)"
      )

      let fallback = DispatchWorkItem { [weak self, weak window] in
        guard let self, let window, window === self.movementBreakWindow else { return }
        if NSApp.isActive {
          window.makeKeyAndOrderFront(nil)
        } else {
          window.orderFrontRegardless()
        }
        self.pendingReminderMovementBreakWindow = nil
        self.reminderMovementBreakRestore = nil
      }
      self.reminderMovementBreakRestore = fallback
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: fallback)
    }
    reminderMovementBreakRestore = show
    DispatchQueue.main.async(execute: show)
  }

  func showManualMovementBreak() {
    dismissStatusMenu()
    if let movementBreakWindow {
      present(movementBreakWindow)
      return
    }

    let window = prepareMovementBreakWindow(
      activity: .stand,
      sourceID: nil,
      fromReminder: false
    )
    present(window)
  }

  func closeWorkout() {
    workoutWindow?.close()
  }

  private func prepareMovementBreakWindow(
    activity: WellnessActivityKind,
    sourceID: String?,
    fromReminder: Bool
  ) -> NSWindow {
    movementBreakWindow?.close()

    let sessionID = UUID()
    let view = MovementBreakView(
      includesWater: activity == .water,
      onComplete: { [weak self] in
        self?.resolveMovementBreak(
          sessionID: sessionID,
          activity: activity,
          sourceID: sourceID,
          fromReminder: fromReminder,
          completed: true
        )
      },
      onCancel: { [weak self] in
        self?.resolveMovementBreak(
          sessionID: sessionID,
          activity: activity,
          sourceID: sourceID,
          fromReminder: fromReminder,
          completed: false
        )
      }
    )
    let window = makeWindow(
      title: activity == .water ? "喝水与起身活动" : "起身活动",
      size: NSSize(width: 620, height: 520),
      minimumSize: NSSize(width: 560, height: 480),
      rootView: view
    )
    let observer = WindowCloseObserver(
      onClose: { [weak self, weak window] in
        guard let window else { return }
        self?.movementBreakWindowDidClose(
          window,
          sessionID: sessionID,
          fromReminder: fromReminder
        )
      },
      onMiniaturize: {},
      onDeminiaturize: {}
    )
    window.delegate = observer

    movementBreakWindow = window
    movementBreakCloseObserver = observer
    movementBreakSessionID = sessionID
    movementBreakDidResolve = false
    return window
  }

  private func resolveMovementBreak(
    sessionID: UUID,
    activity: WellnessActivityKind,
    sourceID: String?,
    fromReminder: Bool,
    completed: Bool
  ) {
    guard movementBreakSessionID == sessionID, !movementBreakDidResolve else { return }
    movementBreakDidResolve = true

    if completed {
      AppModel.shared.completeQuickActivity(activity, sourceID: sourceID)
    } else {
      AppModel.shared.quickActivityDismissed(fromReminder: fromReminder)
    }
    movementBreakWindow?.close()
  }

  private func movementBreakWindowDidClose(
    _ window: NSWindow,
    sessionID: UUID,
    fromReminder: Bool
  ) {
    guard movementBreakWindow === window, movementBreakSessionID == sessionID else { return }
    if !movementBreakDidResolve {
      movementBreakDidResolve = true
      AppModel.shared.quickActivityDismissed(fromReminder: fromReminder)
    }

    reminderMovementBreakRestore?.cancel()
    reminderMovementBreakRestore = nil
    pendingReminderMovementBreakWindow = nil
    movementBreakWindow = nil
    movementBreakCloseObserver = nil
    movementBreakSessionID = nil
    movementBreakDidResolve = false
  }

  func syncReminder(_ occurrence: ReminderOccurrence?) {
    desiredReminder = occurrence
    guard let occurrence else {
      reminderPanel?.orderOut(nil)
      return
    }
    showReminderPanel(occurrence)
  }

  func dismissStatusMenu() {
    guard statusPopoverMode == .menu else { return }
    statusPopover?.close()
    statusPopoverMode = nil
  }

  func applicationDidBecomeActive() {
    if let pendingReminderWorkoutWindow,
      pendingReminderWorkoutWindow === workoutWindow,
      pendingReminderWorkoutWindow.isVisible
    {
      pendingReminderWorkoutWindow.makeKeyAndOrderFront(nil)
      self.pendingReminderWorkoutWindow = nil
      reminderWorkoutRestore?.cancel()
      reminderWorkoutRestore = nil
    }
    if let pendingReminderMovementBreakWindow,
      pendingReminderMovementBreakWindow === movementBreakWindow,
      pendingReminderMovementBreakWindow.isVisible
    {
      pendingReminderMovementBreakWindow.makeKeyAndOrderFront(nil)
      self.pendingReminderMovementBreakWindow = nil
      reminderMovementBreakRestore?.cancel()
      reminderMovementBreakRestore = nil
    }
    if let activeReminder = AppModel.shared.activeReminder {
      showReminderPanel(activeReminder)
    }
    guard let workoutWindow, workoutWindow.isVisible, !workoutWindow.isMiniaturized else { return }
    workoutViewModel?.workoutWindowDidBecomeVisible()
    scheduleInitialCameraAuthorizationRestoreIfNeeded()
  }

  func applicationDidHide() {
    clearInitialCameraAuthorizationRestore()
    workoutViewModel?.workoutWindowDidBecomeHidden()
  }

  func applicationDidChangeScreenParameters() {
    if let activeReminder = AppModel.shared.activeReminder {
      showReminderPanel(activeReminder)
    }
  }

  func popoverDidClose(_ notification: Notification) {
    statusPopoverMode = nil
  }

  @objc private func statusItemClicked(_ sender: Any?) {
    if let activeReminder = AppModel.shared.activeReminder {
      showReminderPanel(activeReminder)
    } else if statusPopover?.isShown == true {
      statusPopover?.close()
      statusPopoverMode = nil
    } else {
      showMenuPopover()
    }
  }

  private func showMenuPopover() {
    guard desiredReminder == nil else { return }
    let view = MenuBarContentView()
      .environmentObject(AppModel.shared)
    presentStatusPopover(
      contentSize: NSSize(width: 330, height: 354),
      contentViewController: NSHostingController(rootView: view)
    )
  }

  private func showReminderPanel(_ occurrence: ReminderOccurrence) {
    statusPopover?.close()
    statusPopoverMode = nil

    let panel: NSPanel
    if let reminderPanel {
      panel = reminderPanel
    } else {
      panel = makeReminderPanel()
      reminderPanel = panel
    }

    updateReminderContent(in: panel, for: occurrence)
    positionReminderPanel(panel)
    panel.orderFrontRegardless()
    reminderLogger.notice(
      "Anchored reminder panel shown; appActive=\(NSApp.isActive, privacy: .public)"
    )

    if occurrence.id != lastAudibleReminderID {
      lastAudibleReminderID = occurrence.id
      if AppModel.shared.settings.soundEnabled {
        NSSound.beep()
      }
    }
  }

  private func makeReminderPanel() -> NSPanel {
    let size = NSSize(width: 390, height: 198)
    let panel = NSPanel(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.level = .floating
    panel.isFloatingPanel = true
    panel.hidesOnDeactivate = false
    panel.becomesKeyOnlyIfNeeded = true
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    panel.isReleasedWhenClosed = false
    panel.isMovable = false
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = true
    panel.animationBehavior = .utilityWindow
    return panel
  }

  private func updateReminderContent(in panel: NSPanel, for occurrence: ReminderOccurrence) {
    guard reminderContentIdentity.shouldRender(occurrence.id) else { return }
    panel.contentViewController = NSHostingController(
      rootView: StatusReminderView()
        .environmentObject(AppModel.shared)
        .id(occurrence.id)
    )
  }

  private func positionReminderPanel(_ panel: NSPanel) {
    guard let button = statusItem?.button, let buttonWindow = button.window else { return }
    let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
    guard let screen = buttonWindow.screen ?? NSScreen.main else { return }
    let visibleFrame = screen.visibleFrame

    let preferredX = buttonFrame.midX - panel.frame.width + 34
    let minimumX = visibleFrame.minX + 8
    let maximumX = visibleFrame.maxX - panel.frame.width - 8
    let origin = NSPoint(
      x: min(max(preferredX, minimumX), maximumX),
      y: buttonFrame.minY - panel.frame.height - 1
    )
    panel.setFrameOrigin(origin)
  }

  private func presentStatusPopover(
    contentSize: NSSize,
    contentViewController: NSViewController
  ) {
    guard let button = statusItem?.button, let popover = statusPopover else { return }

    let show: @MainActor @Sendable () -> Void = { [weak self, weak popover, weak button] in
      guard let self, let popover, let button else { return }
      guard self.desiredReminder == nil else { return }
      popover.behavior = .transient
      popover.contentSize = contentSize
      popover.contentViewController = contentViewController
      self.statusPopoverMode = .menu
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    if popover.isShown {
      popover.close()
      DispatchQueue.main.async(execute: show)
    } else {
      show()
    }
  }

  private func restoreWorkoutWindowAfterInitialCameraAuthorization() {
    guard let workoutWindow,
      workoutViewModel?.canRestoreAfterInitialCameraAuthorization == true,
      workoutWindow.isVisible,
      !workoutWindow.isMiniaturized,
      workoutWindow.isOnActiveSpace,
      !NSApp.isHidden
    else { return }

    clearInitialCameraAuthorizationRestore()
    pendingInitialCameraAuthorizationWindow = workoutWindow
    logger.notice("Camera authorization resolved; waiting for application activation")

    let fallback = DispatchWorkItem { [weak self, weak workoutWindow] in
      guard let self,
        let workoutWindow,
        self.pendingInitialCameraAuthorizationWindow === workoutWindow
      else { return }
      self.finishInitialCameraAuthorizationRestoreIfPossible(
        allowingInactiveVisualFallback: true
      )
    }
    initialCameraAuthorizationRestoreFallback = fallback
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: fallback)

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

  private func finishInitialCameraAuthorizationRestoreIfPossible(
    allowingInactiveVisualFallback: Bool = false
  ) {
    guard let pendingWindow = pendingInitialCameraAuthorizationWindow,
      pendingWindow === workoutWindow,
      workoutViewModel?.canRestoreAfterInitialCameraAuthorization == true,
      pendingWindow.isVisible,
      !pendingWindow.isMiniaturized,
      pendingWindow.isOnActiveSpace,
      !NSApp.isHidden
    else {
      clearInitialCameraAuthorizationRestore()
      return
    }

    if allowingInactiveVisualFallback {
      if NSApp.isActive {
        pendingWindow.makeKeyAndOrderFront(nil)
        logger.notice("Workout window confirmed after camera authorization")
      } else {
        // macOS can decline activation requests from an accessory app. This
        // one-shot fallback only restores visibility after the user-triggered
        // camera prompt; it does not change the window level or stay on top.
        pendingWindow.orderFrontRegardless()
        logger.notice("Workout window restored visibly after activation was declined")
      }
      clearInitialCameraAuthorizationRestore()
      return
    }

    guard NSApp.isActive else {
      requestApplicationActivation()
      return
    }

    pendingWindow.makeKeyAndOrderFront(nil)
    logger.notice("Application became active while camera focus restore was pending")
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
    initialCameraAuthorizationRestoreFallback?.cancel()
    initialCameraAuthorizationRestoreFallback = nil
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
