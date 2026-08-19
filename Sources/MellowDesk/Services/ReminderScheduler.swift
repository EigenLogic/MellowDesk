import Combine
import Foundation
import MellowDeskCore
import UserNotifications

enum ReminderNotificationIdentifier {
  static let legacyRequest = "cn.eigenlogic.mellowdesk.reminder.next"
  static let requestPrefix = "cn.eigenlogic.mellowdesk.reminder."
  static let category = "cn.eigenlogic.mellowdesk.reminder.category"
  static let startWorkoutAction = "cn.eigenlogic.mellowdesk.reminder.start-workout"
  static let snoozeTenMinutesAction = "cn.eigenlogic.mellowdesk.reminder.snooze-ten-minutes"
}

struct ReminderOccurrence: Codable, Equatable, Identifiable, Sendable {
  let dueAt: Date
  let slot: Int

  init(dueAt: Date, slot: Int = WellnessPlan.legacyNeckSlot) {
    self.dueAt = dueAt
    self.slot = WellnessPlan.normalizedSlot(slot)
  }

  var activity: WellnessActivityKind {
    WellnessPlan.activity(for: slot)
  }

  var id: String {
    String(Int64((dueAt.timeIntervalSince1970 * 1_000).rounded()))
  }

  var notificationRequestIdentifier: String {
    ReminderNotificationIdentifier.requestPrefix + id
  }

  private enum CodingKeys: String, CodingKey {
    case dueAt
    case slot
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    dueAt = try container.decode(Date.self, forKey: .dueAt)
    // beta.3 persisted only `dueAt`, and every such occurrence was a neck workout.
    slot = WellnessPlan.normalizedSlot(
      try container.decodeIfPresent(Int.self, forKey: .slot)
        ?? WellnessPlan.legacyNeckSlot
    )
  }
}

@MainActor
protocol ReminderNotificationClient: AnyObject {
  func setDelegate(_ delegate: (any UNUserNotificationCenterDelegate)?)
  func setNotificationCategories(_ categories: Set<UNNotificationCategory>)
  func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
  func authorizationStatus() async -> UNAuthorizationStatus
  func add(_ request: UNNotificationRequest) async throws
  func pendingRequestIdentifiers() async -> Set<String>
  func removePendingNotificationRequests(withIdentifiers identifiers: [String])
  func removeDeliveredNotifications(withIdentifiers identifiers: [String])
}

@MainActor
private final class SystemReminderNotificationClient: ReminderNotificationClient {
  private let center: UNUserNotificationCenter

  init(center: UNUserNotificationCenter = .current()) {
    self.center = center
  }

  func setDelegate(_ delegate: (any UNUserNotificationCenterDelegate)?) {
    center.delegate = delegate
  }

  func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
    center.setNotificationCategories(categories)
  }

  func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
    try await withCheckedThrowingContinuation { continuation in
      center.requestAuthorization(options: options) { granted, error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume(returning: granted)
        }
      }
    }
  }

  func authorizationStatus() async -> UNAuthorizationStatus {
    let settings: UNNotificationSettings = await withCheckedContinuation { continuation in
      center.getNotificationSettings { settings in
        continuation.resume(returning: settings)
      }
    }
    return settings.authorizationStatus
  }

  func add(_ request: UNNotificationRequest) async throws {
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, Error>) in
      center.add(request) { error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume(returning: ())
        }
      }
    }
  }

  func pendingRequestIdentifiers() async -> Set<String> {
    let requests: [UNNotificationRequest] = await withCheckedContinuation { continuation in
      center.getPendingNotificationRequests { requests in
        continuation.resume(returning: requests)
      }
    }
    return Set(requests.map(\.identifier))
  }

  func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
    center.removePendingNotificationRequests(withIdentifiers: identifiers)
  }

  func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
    center.removeDeliveredNotifications(withIdentifiers: identifiers)
  }
}

private final class ReminderNotificationRouter: NSObject, UNUserNotificationCenterDelegate {
  var actionHandler: ((String, String, @escaping () -> Void) -> Void)?
  var presentationHandler:
    ((String, @escaping (UNNotificationPresentationOptions) -> Void) -> Void)?

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    guard let presentationHandler else {
      completionHandler([.banner, .list, .sound])
      return
    }
    presentationHandler(notification.request.identifier, completionHandler)
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    guard let actionHandler else {
      completionHandler()
      return
    }
    actionHandler(
      response.actionIdentifier,
      response.notification.request.identifier,
      completionHandler
    )
  }
}

@MainActor
final class ReminderScheduler: ObservableObject {
  static let nextDueDefaultsKey = "cn.eigenlogic.mellowdesk.reminder.next-due.v1"
  static let activeReminderDefaultsKey = "cn.eigenlogic.mellowdesk.reminder.active.v1"
  static let nextSlotDefaultsKey = "cn.eigenlogic.mellowdesk.reminder.next-slot.v1"
  static let nextSlotDueDefaultsKey = "cn.eigenlogic.mellowdesk.reminder.next-slot-due.v1"

  @Published private(set) var nextDue: Date?
  @Published private(set) var activeReminder: ReminderOccurrence?
  @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
  @Published private(set) var lastErrorDescription: String?

  var nextActivity: WellnessActivityKind {
    activeReminder?.activity
      ?? WellnessPlan.activity(
        for: enabledSlot(startingAt: scheduledSlot, settings: resolvedSettings())
      )
  }

  private let notificationClient: ReminderNotificationClient
  private let defaults: UserDefaults
  private let calendar: Calendar
  private let router: ReminderNotificationRouter
  private var activeSettings: AppSettings?
  private var rolloverTask: Task<Void, Never>?
  private var isActivityActive = false
  private var inProgressReminderSlot: Int?
  private var scheduledSlot: Int
  private var scheduleRevision: UInt = 0

  convenience init(
    notificationCenter: UNUserNotificationCenter = .current(),
    defaults: UserDefaults = .standard,
    calendar: Calendar = .current
  ) {
    self.init(
      notificationClient: SystemReminderNotificationClient(center: notificationCenter),
      defaults: defaults,
      calendar: calendar
    )
  }

  init(
    notificationClient: ReminderNotificationClient,
    defaults: UserDefaults = .standard,
    calendar: Calendar = .current
  ) {
    self.notificationClient = notificationClient
    self.defaults = defaults
    self.calendar = calendar
    router = ReminderNotificationRouter()

    let restoredNextDue: Date?
    if let timestamp = defaults.object(forKey: Self.nextDueDefaultsKey) as? Double {
      restoredNextDue = Date(timeIntervalSince1970: timestamp)
      nextDue = Date(timeIntervalSince1970: timestamp)
    } else {
      restoredNextDue = nil
      nextDue = nil
    }

    let persistedSlot = defaults.object(forKey: Self.nextSlotDefaultsKey) as? Int
    let persistedSlotDue = defaults.object(forKey: Self.nextSlotDueDefaultsKey) as? Double
    if let persistedSlot,
      restoredNextDue == nil
        || persistedSlotDue.map({
          abs($0 - (restoredNextDue?.timeIntervalSince1970 ?? $0)) < 0.001
        }) == true
    {
      scheduledSlot = WellnessPlan.normalizedSlot(persistedSlot)
    } else {
      // A future beta.3 reminder was always a neck workout. A genuinely new
      // installation starts with the most useful whole-body break instead.
      scheduledSlot = restoredNextDue == nil ? 0 : WellnessPlan.legacyNeckSlot
    }

    if let data = defaults.data(forKey: Self.activeReminderDefaultsKey),
      let occurrence = try? JSONDecoder().decode(ReminderOccurrence.self, from: data)
    {
      activeReminder = occurrence
      nextDue = occurrence.dueAt
      scheduledSlot = occurrence.slot
    } else {
      activeReminder = nil
    }

    router.actionHandler = { [weak self] actionIdentifier, requestIdentifier, completion in
      Task { @MainActor [weak self] in
        await self?.handleNotificationAction(
          actionIdentifier,
          requestIdentifier: requestIdentifier
        )
        completion()
      }
    }
    router.presentationHandler = { [weak self] requestIdentifier, completion in
      Task { @MainActor [weak self] in
        if self?.isActivityActive == true
          || self?.activeReminder?.notificationRequestIdentifier == requestIdentifier
        {
          completion([])
        } else {
          completion([.banner, .list, .sound])
        }
      }
    }
    notificationClient.setDelegate(router)
    registerNotificationCategory()
  }

  /// Call once during app startup. Future persisted dates are restored, while overdue
  /// reminders become a durable occurrence that waits for an explicit user action.
  func activate(settings: AppSettings, now: Date = Date()) async {
    activeSettings = settings
    notificationClient.removePendingNotificationRequests(
      withIdentifiers: [ReminderNotificationIdentifier.legacyRequest]
    )
    notificationClient.removeDeliveredNotifications(
      withIdentifiers: [ReminderNotificationIdentifier.legacyRequest]
    )
    _ = await requestAuthorization()

    if activeReminder != nil {
      if let pauseUntil = settings.pauseUntil, pauseUntil > now {
        clearActiveReminder()
        await settingsDidChange(settings, now: now)
      } else if let activeReminder {
        setScheduledSlot(activeReminder.slot)
        setPersistedNextDue(activeReminder.dueAt)
      }
      return
    }

    if let persistedDue = nextDue {
      if persistedDue <= now {
        markReminderDue(at: persistedDue)
      } else if settings.pauseUntil.map({ persistedDue > $0 }) ?? true {
        await replacePendingNotification(dueAt: persistedDue, settings: settings, now: now)
      } else {
        await settingsDidChange(settings, now: now)
      }
    } else {
      await settingsDidChange(settings, now: now)
    }
  }

  @discardableResult
  func requestAuthorization() async -> Bool {
    registerNotificationCategory()
    let granted: Bool
    do {
      granted = try await notificationClient.requestAuthorization(options: [.alert, .sound])
      lastErrorDescription = nil
    } catch {
      granted = false
      lastErrorDescription = error.localizedDescription
    }
    await refreshAuthorizationStatus()
    return granted
  }

  func refreshAuthorizationStatus() async {
    authorizationStatus = await notificationClient.authorizationStatus()
  }

  /// Reconciles the durable due date when the app activates, wakes, or the system clock changes.
  func refreshIfNeeded(settings: AppSettings, now: Date = Date()) async {
    activeSettings = settings
    await refreshAuthorizationStatus()
    await reconcileDue(settings: settings, now: now)
  }

  /// Shared due transition used by timers, activation, wake, and deterministic tests.
  func reconcileDue(settings: AppSettings, now: Date = Date()) async {
    activeSettings = settings
    guard !isActivityActive else {
      cancelNextReminder()
      return
    }

    if let activeReminder {
      setPersistedNextDue(activeReminder.dueAt)
      return
    }

    guard let nextDue else {
      await settingsDidChange(settings, now: now)
      return
    }

    if nextDue <= now {
      markReminderDue(at: nextDue)
    } else if await hasPendingReminder(dueAt: nextDue) {
      armRollover(after: nextDue)
    } else {
      await replacePendingNotification(dueAt: nextDue, settings: settings, now: now)
    }
  }

  func settingsDidChange(_ settings: AppSettings, now: Date = Date()) async {
    activeSettings = settings
    guard !isActivityActive else {
      cancelNextReminder()
      return
    }
    // An already-due reminder is a user-visible occurrence, not part of the future
    // schedule. Ordinary settings edits must not dismiss it behind the user's back.
    guard activeReminder == nil else { return }
    let due = nextScheduledDate(after: now, settings: settings)
    await replacePendingNotification(dueAt: due, settings: settings, now: now)
  }

  /// Synchronously persists the completed rotation before any asynchronous system
  /// notification work. Callers can safely close their window or terminate afterward.
  @discardableResult
  func recordActivityCompletion(
    at completionDate: Date = Date(),
    settings: AppSettings
  ) -> Date? {
    isActivityActive = false
    activeSettings = settings
    clearActiveReminder()
    if let completedSlot = inProgressReminderSlot {
      setScheduledSlot(enabledSlot(startingAt: completedSlot + 1, settings: settings))
    }
    inProgressReminderSlot = nil
    let due = nextScheduledDate(after: completionDate, settings: settings)
    setPersistedNextDue(due)
    if let due {
      armRollover(after: due)
    }
    return due
  }

  func activityCompleted(at completionDate: Date = Date(), settings: AppSettings) async {
    let due = recordActivityCompletion(at: completionDate, settings: settings)
    await replacePendingNotification(dueAt: due, settings: settings, now: completionDate)
  }

  func workoutCompleted(at completionDate: Date = Date(), settings: AppSettings) async {
    await activityCompleted(at: completionDate, settings: settings)
  }

  /// Re-enters the normal cadence without advancing the rotation when an activity
  /// is closed before it is recorded as complete.
  func activityDismissed(
    at date: Date = Date(),
    settings: AppSettings,
    snoozeMinutes: Int? = nil,
    advanceRotation: Bool = false
  ) async {
    isActivityActive = false
    activeSettings = settings
    clearActiveReminder()
    if let interruptedSlot = inProgressReminderSlot {
      setScheduledSlot(interruptedSlot + (advanceRotation ? 1 : 0))
    }
    inProgressReminderSlot = nil
    let due: Date?
    if let snoozeMinutes {
      let candidate = date.addingTimeInterval(TimeInterval(max(1, snoozeMinutes) * 60))
      if let pauseUntil = settings.pauseUntil, pauseUntil > candidate {
        due = settings.reminderSchedule.nextReminder(after: pauseUntil, calendar: calendar)
      } else {
        due = settings.reminderSchedule.adjustedToWorkWindow(candidate, calendar: calendar)
      }
    } else {
      due = nextScheduledDate(after: date, settings: settings)
    }
    await replacePendingNotification(dueAt: due, settings: settings, now: date)
  }

  func workoutDismissed(
    at date: Date = Date(),
    settings: AppSettings,
    advanceRotation: Bool = false
  ) async {
    await activityDismissed(
      at: date,
      settings: settings,
      advanceRotation: advanceRotation
    )
  }

  func snoozeTenMinutes(from date: Date = Date(), settings: AppSettings) async {
    activeSettings = settings
    guard !isActivityActive else { return }
    if let activeReminder {
      setScheduledSlot(activeReminder.slot)
    }
    clearActiveReminder()

    let candidate = date.addingTimeInterval(10 * 60)
    let due: Date?
    if let pauseUntil = settings.pauseUntil, pauseUntil > candidate {
      due = settings.reminderSchedule.nextReminder(after: pauseUntil, calendar: calendar)
    } else {
      due = settings.reminderSchedule.adjustedToWorkWindow(candidate, calendar: calendar)
    }
    await replacePendingNotification(dueAt: due, settings: settings, now: date)
  }

  /// A finite pause schedules the next valid reminder after the pause expires.
  func pause(until date: Date, settings: AppSettings, now: Date = Date()) async {
    var pausedSettings = settings
    pausedSettings.pauseUntil = date
    activeSettings = pausedSettings
    if let activeReminder {
      setScheduledSlot(activeReminder.slot)
    }
    clearActiveReminder()
    guard !isActivityActive else { return }
    let due = nextScheduledDate(after: now, settings: pausedSettings)
    await replacePendingNotification(dueAt: due, settings: pausedSettings, now: now)
  }

  func cancelNextReminder() {
    scheduleRevision &+= 1
    rolloverTask?.cancel()
    rolloverTask = nil
    let identifiers = knownRequestIdentifiers()
    notificationClient.removePendingNotificationRequests(withIdentifiers: identifiers)
    notificationClient.removeDeliveredNotifications(withIdentifiers: identifiers)
    setActiveReminder(nil)
    setPersistedNextDue(nil)
    lastErrorDescription = nil
  }

  /// Stops only process-local work. Durable reminder state and the system fallback
  /// intentionally survive app restarts and system logout/login cycles.
  func shutdown() {
    scheduleRevision &+= 1
    rolloverTask?.cancel()
    rolloverTask = nil
  }

  func activityStarted() {
    isActivityActive = true
    cancelNextReminder()
  }

  @discardableResult
  func activityStarted(reminderID: ReminderOccurrence.ID) -> Bool {
    guard let occurrence = activeReminder, occurrence.id == reminderID else { return false }
    inProgressReminderSlot = occurrence.slot
    setScheduledSlot(occurrence.slot)
    activityStarted()
    return true
  }

  func workoutStarted() {
    activityStarted()
  }

  @discardableResult
  func workoutStarted(reminderID: ReminderOccurrence.ID) -> Bool {
    activityStarted(reminderID: reminderID)
  }

  private func registerNotificationCategory() {
    let start = UNNotificationAction(
      identifier: ReminderNotificationIdentifier.startWorkoutAction,
      title: "现在开始",
      options: [.foreground]
    )
    let snooze = UNNotificationAction(
      identifier: ReminderNotificationIdentifier.snoozeTenMinutesAction,
      title: "推迟 10 分钟"
    )
    let category = UNNotificationCategory(
      identifier: ReminderNotificationIdentifier.category,
      actions: [start, snooze],
      intentIdentifiers: [],
      options: []
    )
    notificationClient.setNotificationCategories([category])
  }

  func handleNotificationAction(
    _ actionIdentifier: String,
    requestIdentifier: String
  ) async {
    guard isRelevantReminderRequest(requestIdentifier) else { return }

    switch actionIdentifier {
    case ReminderNotificationIdentifier.snoozeTenMinutesAction:
      await snoozeTenMinutes(settings: resolvedSettings())

    case ReminderNotificationIdentifier.startWorkoutAction,
      UNNotificationDefaultActionIdentifier:
      if activeReminder == nil, let nextDue {
        markReminderDue(at: nextDue)
      }
      guard let activeReminder else { return }
      NotificationCenter.default.post(
        name: .mellowDeskStartActivityRequested,
        object: activeReminder.id
      )

    default:
      break
    }
  }

  private func isRelevantReminderRequest(_ requestIdentifier: String) -> Bool {
    if activeReminder?.notificationRequestIdentifier == requestIdentifier { return true }
    if let nextDue {
      return ReminderOccurrence(dueAt: nextDue).notificationRequestIdentifier == requestIdentifier
    }
    return false
  }

  private func resolvedSettings() -> AppSettings {
    if let activeSettings {
      return activeSettings
    }
    guard
      let data = defaults.data(forKey: SettingsStore.storageKey),
      let stored = try? JSONDecoder().decode(AppSettings.self, from: data)
    else {
      return .default
    }
    return stored
  }

  private func nextScheduledDate(after date: Date, settings: AppSettings) -> Date? {
    let baseline: Date
    if let pauseUntil = settings.pauseUntil, pauseUntil > date {
      baseline = pauseUntil
    } else {
      baseline = date
    }
    return settings.reminderSchedule.nextReminder(after: baseline, calendar: calendar)
  }

  private func replacePendingNotification(
    dueAt due: Date?,
    settings: AppSettings,
    now: Date
  ) async {
    scheduleRevision &+= 1
    let revision = scheduleRevision
    rolloverTask?.cancel()
    rolloverTask = nil
    notificationClient.removePendingNotificationRequests(
      withIdentifiers: knownRequestIdentifiers()
    )

    guard !isActivityActive else {
      setPersistedNextDue(nil)
      lastErrorDescription = nil
      return
    }

    guard let due else {
      setPersistedNextDue(nil)
      lastErrorDescription = nil
      return
    }

    let occurrence = ReminderOccurrence(
      dueAt: due,
      slot: enabledSlot(startingAt: scheduledSlot, settings: settings)
    )
    setScheduledSlot(occurrence.slot)
    setPersistedNextDue(due)
    armRollover(after: due)
    lastErrorDescription = nil

    let content = UNMutableNotificationContent()
    switch occurrence.activity {
    case .stand:
      content.title = "起来走两步吧"
      content.body = "离开椅子活动 2 分钟，轻松走动就算完成。"
    case .water:
      content.title = "要不要喝几口水？"
      content.body = "起身接点水，顺便活动 2 分钟；按自己的节奏喝就好。"
    case .neck:
      content.title = "给颈肩 3 分钟"
      content.body = "跟着动画缓慢活动，只做到舒适范围。"
    case .pelvicFloor:
      content.title = "来一组提肛跟练"
      content.body = "跟随 2 分钟节奏收提与放松，坐着或站着都可以。"
    }
    content.categoryIdentifier = ReminderNotificationIdentifier.category
    content.threadIdentifier = "cn.eigenlogic.mellowdesk.reminders"
    if settings.soundEnabled {
      content.sound = .default
    }

    // The app-owned card appears at `due`. This notification is a short fallback for
    // sleep, App Nap, or an app process that is not running at that moment.
    let fallbackDate = due.addingTimeInterval(5)
    let trigger = UNTimeIntervalNotificationTrigger(
      timeInterval: max(1, fallbackDate.timeIntervalSince(now)),
      repeats: false
    )
    let request = UNNotificationRequest(
      identifier: occurrence.notificationRequestIdentifier,
      content: content,
      trigger: trigger
    )

    do {
      try await notificationClient.add(request)
      guard revision == scheduleRevision, !isActivityActive else {
        if !isActivityActive,
          activeReminder == nil,
          nextDue == due
        {
          // A same-due refresh uses the same identifier. This successful add may
          // replace newer content, but it still leaves the correct due fallback
          // present. Keep it instead of deleting or recursively rescheduling it.
          return
        } else {
          notificationClient.removePendingNotificationRequests(
            withIdentifiers: [occurrence.notificationRequestIdentifier]
          )
        }
        return
      }
    } catch {
      // The in-app timer remains armed even if system notifications are unavailable.
      guard revision == scheduleRevision else { return }
      lastErrorDescription = error.localizedDescription
    }
  }

  private func hasPendingReminder(dueAt due: Date) async -> Bool {
    let identifiers = await notificationClient.pendingRequestIdentifiers()
    return identifiers.contains(ReminderOccurrence(dueAt: due).notificationRequestIdentifier)
  }

  private func armRollover(after due: Date) {
    rolloverTask?.cancel()
    let delay = max(0.05, due.timeIntervalSinceNow)
    let maximumDelay = 14.0 * 24 * 60 * 60
    let nanoseconds = UInt64(min(delay, maximumDelay) * 1_000_000_000)

    rolloverTask = Task { @MainActor [weak self] in
      do {
        try await Task.sleep(nanoseconds: nanoseconds)
      } catch {
        return
      }
      guard let self, !Task.isCancelled else { return }
      await self.reconcileDue(settings: self.resolvedSettings(), now: Date())
    }
  }

  private func markReminderDue(at due: Date) {
    scheduleRevision &+= 1
    rolloverTask?.cancel()
    rolloverTask = nil
    let occurrence = ReminderOccurrence(dueAt: due, slot: scheduledSlot)
    notificationClient.removePendingNotificationRequests(
      withIdentifiers: [
        occurrence.notificationRequestIdentifier,
        ReminderNotificationIdentifier.legacyRequest,
      ]
    )
    setPersistedNextDue(due)
    setActiveReminder(occurrence)
    lastErrorDescription = nil
  }

  private func clearActiveReminder() {
    guard let activeReminder else { return }
    let identifier = activeReminder.notificationRequestIdentifier
    notificationClient.removePendingNotificationRequests(withIdentifiers: [identifier])
    notificationClient.removeDeliveredNotifications(withIdentifiers: [identifier])
    setActiveReminder(nil)
  }

  private func knownRequestIdentifiers() -> [String] {
    var identifiers: Set<String> = [ReminderNotificationIdentifier.legacyRequest]
    if let nextDue {
      identifiers.insert(ReminderOccurrence(dueAt: nextDue).notificationRequestIdentifier)
    }
    if let activeReminder {
      identifiers.insert(activeReminder.notificationRequestIdentifier)
    }
    return Array(identifiers)
  }

  private func setPersistedNextDue(_ date: Date?) {
    nextDue = date
    if let date {
      defaults.set(date.timeIntervalSince1970, forKey: Self.nextDueDefaultsKey)
      defaults.set(date.timeIntervalSince1970, forKey: Self.nextSlotDueDefaultsKey)
    } else {
      defaults.removeObject(forKey: Self.nextDueDefaultsKey)
      defaults.removeObject(forKey: Self.nextSlotDueDefaultsKey)
    }
  }

  private func setActiveReminder(_ occurrence: ReminderOccurrence?) {
    activeReminder = occurrence
    if let occurrence, let data = try? JSONEncoder().encode(occurrence) {
      setScheduledSlot(occurrence.slot)
      defaults.set(data, forKey: Self.activeReminderDefaultsKey)
    } else {
      defaults.removeObject(forKey: Self.activeReminderDefaultsKey)
    }
  }

  private func setScheduledSlot(_ slot: Int) {
    scheduledSlot = WellnessPlan.normalizedSlot(slot)
    defaults.set(scheduledSlot, forKey: Self.nextSlotDefaultsKey)
  }

  private func enabledSlot(startingAt slot: Int, settings: AppSettings) -> Int {
    let normalized = WellnessPlan.normalizedSlot(slot)
    if WellnessPlan.activity(for: normalized) == .pelvicFloor,
      !settings.pelvicFloorTrainingEnabled
    {
      return WellnessPlan.normalizedSlot(normalized + 1)
    }
    return normalized
  }
}
