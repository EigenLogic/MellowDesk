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
    case workout
    case movement(UUID)
    case pelvicFloor

    var isActivity: Bool {
      self != .menu
    }
  }

  private var dashboardWindow: NSWindow?
  private var settingsWindow: NSWindow?
  private var workoutViewModel: WorkoutViewModel?
  private var movementBreakSessionID: UUID?
  private var movementBreakDidResolve = false
  private var statusItem: NSStatusItem?
  private var statusPopover: NSPopover?
  private var statusPopoverMode: StatusPopoverMode?
  private var reminderPanel: NSPanel?
  private var reminderContentIdentity = ReminderContentIdentity()
  private var desiredReminder: ReminderOccurrence?
  private var lastAudibleReminderID: String?
  private var updateReadyWindow: NSWindow?
  private var updateReadyVersion: String?
  private var updateReadyCloseObserver: WindowCloseObserver?
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

  func showUpdateReadyPrompt(version: String) {
    dismissStatusMenu()
    setUpdateReadyStatusItem(true)
    if let updateReadyWindow {
      if updateReadyVersion == version {
        present(updateReadyWindow)
        return
      }
      updateReadyWindow.close()
    }

    let view = UpdateReadyView(
      version: version,
      onInstall: {
        AppModel.shared.installReadyUpdate()
      },
      onLater: { [weak self] in
        self?.dismissUpdateReadyPrompt()
      }
    )
    let window = makeWindow(
      title: "软件更新",
      size: NSSize(width: 500, height: 240),
      minimumSize: NSSize(width: 500, height: 240),
      rootView: view
    )
    window.styleMask.remove(.miniaturizable)
    window.styleMask.remove(.resizable)
    window.setContentSize(NSSize(width: 500, height: 240))
    window.minSize = NSSize(width: 500, height: 240)
    window.maxSize = NSSize(width: 500, height: 240)
    window.level = .floating
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

    let observer = WindowCloseObserver(
      onClose: { [weak self, weak window] in
        guard let self, let window, window === updateReadyWindow else { return }
        updateReadyWindow = nil
        updateReadyVersion = nil
        updateReadyCloseObserver = nil
      },
      onMiniaturize: {},
      onDeminiaturize: {}
    )
    window.delegate = observer
    updateReadyWindow = window
    updateReadyVersion = version
    updateReadyCloseObserver = observer
    present(window)
  }

  func dismissUpdateReadyPrompt() {
    updateReadyWindow?.close()
  }

  func clearUpdateReadyStatus() {
    setUpdateReadyStatusItem(false)
  }

  func showWorkout() {
    if workoutViewModel != nil {
      showCurrentActivityPopover()
      return
    }
    guard statusPopoverMode?.isActivity != true else {
      showCurrentActivityPopover()
      return
    }

    let viewModel = WorkoutViewModel(
      appModel: AppModel.shared,
      initialCameraAuthorizationDidResolve: { [weak self] in
        self?.restoreWorkoutPopoverAfterInitialCameraAuthorization()
      }
    )
    let view = WorkoutView(viewModel: viewModel)
      .environmentObject(AppModel.shared)
    workoutViewModel = viewModel
    presentStatusPopover(
      mode: .workout,
      contentSize: NSSize(width: 1000, height: 700),
      behavior: .applicationDefined,
      contentViewController: NSHostingController(rootView: view)
    )
  }

  func showWorkoutFromReminder() {
    DispatchQueue.main.async { [weak self] in
      self?.showWorkout()
    }
  }

  func showMovementBreakFromReminder(_ occurrence: ReminderOccurrence) {
    guard occurrence.activity.isQuickActivity else { return }
    DispatchQueue.main.async { [weak self] in
      self?.prepareMovementBreakPopover(
        activity: occurrence.activity,
        sourceID: occurrence.id
      )
    }
  }

  func showManualMovementBreak() {
    if movementBreakSessionID != nil {
      showCurrentActivityPopover()
      return
    }
    prepareMovementBreakPopover(activity: .stand, sourceID: nil)
  }

  func showPelvicFloorBreak() {
    if statusPopoverMode == .pelvicFloor {
      showCurrentActivityPopover()
      return
    }
    guard statusPopoverMode?.isActivity != true else {
      showCurrentActivityPopover()
      return
    }

    let view = PelvicFloorBreakView(
      onClose: { [weak self] in
        self?.finishPelvicFloorBreak()
      }
    )
    presentStatusPopover(
      mode: .pelvicFloor,
      contentSize: NSSize(width: 560, height: 700),
      behavior: .applicationDefined,
      contentViewController: NSHostingController(rootView: view)
    )
  }

  func closeWorkout(skipped: Bool = false) {
    guard let workoutViewModel else { return }
    workoutViewModel.windowDidClose(skipped: skipped)
    self.workoutViewModel = nil
    finishStatusActivity(mode: .workout)
  }

  private func prepareMovementBreakPopover(
    activity: WellnessActivityKind,
    sourceID: String?
  ) {
    guard statusPopoverMode?.isActivity != true else {
      showCurrentActivityPopover()
      return
    }

    let sessionID = UUID()
    let view = MovementBreakView(
      includesWater: activity == .water,
      onComplete: { [weak self] in
        self?.resolveMovementBreak(
          sessionID: sessionID,
          activity: activity,
          sourceID: sourceID,
          completed: true
        )
      },
      onCancel: { [weak self] in
        self?.resolveMovementBreak(
          sessionID: sessionID,
          activity: activity,
          sourceID: sourceID,
          completed: false
        )
      }
    )
    movementBreakSessionID = sessionID
    movementBreakDidResolve = false
    presentStatusPopover(
      mode: .movement(sessionID),
      contentSize: NSSize(width: 620, height: 520),
      behavior: .applicationDefined,
      contentViewController: NSHostingController(rootView: view)
    )
  }

  private func resolveMovementBreak(
    sessionID: UUID,
    activity: WellnessActivityKind,
    sourceID: String?,
    completed: Bool
  ) {
    guard movementBreakSessionID == sessionID, !movementBreakDidResolve else { return }
    movementBreakDidResolve = true

    if completed {
      AppModel.shared.completeQuickActivity(activity, sourceID: sourceID)
    } else {
      AppModel.shared.quickActivitySkipped()
    }
    movementBreakSessionID = nil
    movementBreakDidResolve = false
    finishStatusActivity(mode: .movement(sessionID))
  }

  private func finishPelvicFloorBreak() {
    guard statusPopoverMode == .pelvicFloor else { return }
    AppModel.shared.pelvicFloorBreakDismissed()
    finishStatusActivity(mode: .pelvicFloor)
  }

  func syncReminder(_ occurrence: ReminderOccurrence?) {
    desiredReminder = occurrence
    guard let occurrence else {
      reminderPanel?.orderOut(nil)
      return
    }
    guard statusPopoverMode?.isActivity != true else { return }
    showReminderPanel(occurrence)
  }

  func dismissStatusMenu() {
    guard statusPopoverMode == .menu else { return }
    statusPopover?.close()
    statusPopoverMode = nil
  }

  func applicationDidBecomeActive() {
    if statusPopoverMode == .workout, statusPopover?.isShown == true {
      workoutViewModel?.workoutWindowDidBecomeVisible()
    }
    if statusPopoverMode?.isActivity != true,
      let activeReminder = AppModel.shared.activeReminder
    {
      showReminderPanel(activeReminder)
    }
  }

  func applicationDidHide() {
    workoutViewModel?.workoutWindowDidBecomeHidden()
  }

  func applicationDidChangeScreenParameters() {
    if let activeReminder = AppModel.shared.activeReminder {
      showReminderPanel(activeReminder)
    }
  }

  func popoverDidClose(_ notification: Notification) {
    switch statusPopoverMode {
    case .menu:
      statusPopoverMode = nil
    case .workout:
      workoutViewModel?.workoutWindowDidBecomeHidden()
    case .movement, .pelvicFloor, .none:
      break
    }
  }

  @objc private func statusItemClicked(_ sender: Any?) {
    if statusPopoverMode?.isActivity == true {
      if statusPopover?.isShown == true {
        statusPopover?.close()
      } else {
        showCurrentActivityPopover()
      }
    } else if let activeReminder = AppModel.shared.activeReminder {
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
      mode: .menu,
      contentSize: MenuBarContentView.contentSize(
        for: AppModel.shared.settings,
        updateReady: AppModel.shared.readyUpdateVersion != nil
      ),
      behavior: .transient,
      contentViewController: NSHostingController(rootView: view)
    )
  }

  private func showReminderPanel(_ occurrence: ReminderOccurrence) {
    guard statusPopoverMode?.isActivity != true else { return }
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
    mode: StatusPopoverMode,
    contentSize: NSSize,
    behavior: NSPopover.Behavior,
    contentViewController: NSViewController
  ) {
    guard let button = statusItem?.button, let popover = statusPopover else { return }

    let show: @MainActor @Sendable () -> Void = { [weak self, weak popover, weak button] in
      guard let self, let popover, let button else { return }
      if mode == .menu {
        guard self.desiredReminder == nil else { return }
      } else {
        self.reminderPanel?.orderOut(nil)
      }
      popover.behavior = behavior
      popover.contentSize = contentSize
      popover.contentViewController = contentViewController
      self.statusPopoverMode = mode
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
      if mode.isActivity {
        popover.contentViewController?.view.window?.level = .floating
        popover.contentViewController?.view.window?.hidesOnDeactivate = false
      }
      if mode == .workout {
        self.workoutViewModel?.workoutWindowDidBecomeVisible()
      }
    }

    if popover.isShown {
      popover.close()
      DispatchQueue.main.async(execute: show)
    } else {
      show()
    }
  }

  private func showCurrentActivityPopover() {
    guard statusPopoverMode?.isActivity == true,
      let button = statusItem?.button,
      let popover = statusPopover
    else { return }
    popover.behavior = .applicationDefined
    if !popover.isShown {
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
    popover.contentViewController?.view.window?.level = .floating
    popover.contentViewController?.view.window?.hidesOnDeactivate = false
    if statusPopoverMode == .workout {
      workoutViewModel?.workoutWindowDidBecomeVisible()
    }
  }

  private func finishStatusActivity(mode: StatusPopoverMode) {
    guard statusPopoverMode == mode else { return }
    statusPopoverMode = nil
    statusPopover?.close()
    statusPopover?.contentViewController = NSViewController()
  }

  private func restoreWorkoutPopoverAfterInitialCameraAuthorization() {
    guard statusPopoverMode == .workout,
      workoutViewModel?.canRestoreAfterInitialCameraAuthorization == true
    else { return }
    DispatchQueue.main.async { [weak self] in
      self?.showCurrentActivityPopover()
    }
  }

  private func setUpdateReadyStatusItem(_ isReady: Bool) {
    guard let button = statusItem?.button else { return }
    let symbolName = isReady ? "arrow.down.circle.fill" : "leaf.fill"
    let description = isReady ? "小桌伴更新已准备好" : "小桌伴"
    let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
    image?.isTemplate = true
    button.image = image
    button.toolTip = description
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
