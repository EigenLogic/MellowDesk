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

  var id: String {
    String(Int64((dueAt.timeIntervalSince1970 * 1_000).rounded()))
  }

  var notificationRequestIdentifier: String {
    ReminderNotificationIdentifier.requestPrefix + id
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

  @Published private(set) var nextDue: Date?
  @Published private(set) var activeReminder: ReminderOccurrence?
  @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
  @Published private(set) var lastErrorDescription: String?

  private let notificationClient: ReminderNotificationClient
  private let defaults: UserDefaults
  private let calendar: Calendar
  private let router: ReminderNotificationRouter
  private var activeSettings: AppSettings?
  private var rolloverTask: Task<Void, Never>?
  private var isWorkoutActive = false
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

    if let timestamp = defaults.object(forKey: Self.nextDueDefaultsKey) as? Double {
      nextDue = Date(timeIntervalSince1970: timestamp)
    } else {
      nextDue = nil
    }

    if let data = defaults.data(forKey: Self.activeReminderDefaultsKey),
      let occurrence = try? JSONDecoder().decode(ReminderOccurrence.self, from: data)
    {
      activeReminder = occurrence
      nextDue = occurrence.dueAt
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
        if self?.isWorkoutActive == true
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
    guard !isWorkoutActive else {
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
    guard !isWorkoutActive else {
      cancelNextReminder()
      return
    }
    // An already-due reminder is a user-visible occurrence, not part of the future
    // schedule. Ordinary settings edits must not dismiss it behind the user's back.
    guard activeReminder == nil else { return }
    let due = nextScheduledDate(after: now, settings: settings)
    await replacePendingNotification(dueAt: due, settings: settings, now: now)
  }

  func workoutCompleted(at completionDate: Date = Date(), settings: AppSettings) async {
    isWorkoutActive = false
    activeSettings = settings
    clearActiveReminder()
    let due = nextScheduledDate(after: completionDate, settings: settings)
    await replacePendingNotification(dueAt: due, settings: settings, now: completionDate)
  }

  /// Re-enters the normal cadence when a started workout is closed without a saved session.
  func workoutDismissed(at date: Date = Date(), settings: AppSettings) async {
    isWorkoutActive = false
    activeSettings = settings
    clearActiveReminder()
    let due = nextScheduledDate(after: date, settings: settings)
    await replacePendingNotification(dueAt: due, settings: settings, now: date)
  }

  func snoozeTenMinutes(from date: Date = Date(), settings: AppSettings) async {
    activeSettings = settings
    guard !isWorkoutActive else { return }
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
    clearActiveReminder()
    guard !isWorkoutActive else { return }
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

  func workoutStarted() {
    isWorkoutActive = true
    cancelNextReminder()
  }

  @discardableResult
  func workoutStarted(reminderID: ReminderOccurrence.ID) -> Bool {
    guard activeReminder?.id == reminderID else { return false }
    workoutStarted()
    return true
  }

  private func registerNotificationCategory() {
    let start = UNNotificationAction(
      identifier: ReminderNotificationIdentifier.startWorkoutAction,
      title: "开始训练",
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
      workoutStarted()
      NotificationCenter.default.post(name: .mellowDeskStartWorkoutRequested, object: nil)

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

    guard !isWorkoutActive else {
      setPersistedNextDue(nil)
      lastErrorDescription = nil
      return
    }

    guard let due else {
      setPersistedNextDue(nil)
      lastErrorDescription = nil
      return
    }

    let occurrence = ReminderOccurrence(dueAt: due)
    setPersistedNextDue(due)
    armRollover(after: due)
    lastErrorDescription = nil

    let content = UNMutableNotificationContent()
    content.title = "该活动一下颈肩了"
    content.body = "用 2–3 分钟完成一次颈肩微运动。"
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
      guard revision == scheduleRevision, !isWorkoutActive else {
        if !isWorkoutActive,
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
    let occurrence = ReminderOccurrence(dueAt: due)
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
    } else {
      defaults.removeObject(forKey: Self.nextDueDefaultsKey)
    }
  }

  private func setActiveReminder(_ occurrence: ReminderOccurrence?) {
    activeReminder = occurrence
    if let occurrence, let data = try? JSONEncoder().encode(occurrence) {
      defaults.set(data, forKey: Self.activeReminderDefaultsKey)
    } else {
      defaults.removeObject(forKey: Self.activeReminderDefaultsKey)
    }
  }
}
