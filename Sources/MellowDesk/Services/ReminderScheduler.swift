import Combine
import Foundation
import MellowDeskCore
import UserNotifications

enum ReminderNotificationIdentifier {
  static let request = "cn.eigenlogic.mellowdesk.reminder.next"
  static let category = "cn.eigenlogic.mellowdesk.reminder.category"
  static let startWorkoutAction = "cn.eigenlogic.mellowdesk.reminder.start-workout"
  static let snoozeTenMinutesAction = "cn.eigenlogic.mellowdesk.reminder.snooze-ten-minutes"
}

private final class ReminderNotificationRouter: NSObject, UNUserNotificationCenterDelegate {
  var actionHandler: ((String, @escaping () -> Void) -> Void)?
  var presentationHandler:
    ((UNNotification, @escaping (UNNotificationPresentationOptions) -> Void) -> Void)?

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    guard let presentationHandler else {
      completionHandler([.banner, .list, .sound])
      return
    }
    presentationHandler(notification, completionHandler)
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
    actionHandler(response.actionIdentifier, completionHandler)
  }
}

@MainActor
final class ReminderScheduler: ObservableObject {
  static let nextDueDefaultsKey = "cn.eigenlogic.mellowdesk.reminder.next-due.v1"

  @Published private(set) var nextDue: Date?
  @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
  @Published private(set) var lastErrorDescription: String?

  private let notificationCenter: UNUserNotificationCenter
  private let defaults: UserDefaults
  private let calendar: Calendar
  private let router: ReminderNotificationRouter
  private var activeSettings: AppSettings?
  private var rolloverTask: Task<Void, Never>?
  private var isWorkoutActive = false
  private var scheduleRevision: UInt = 0

  init(
    notificationCenter: UNUserNotificationCenter = .current(),
    defaults: UserDefaults = .standard,
    calendar: Calendar = .current
  ) {
    self.notificationCenter = notificationCenter
    self.defaults = defaults
    self.calendar = calendar
    router = ReminderNotificationRouter()

    if let timestamp = defaults.object(forKey: Self.nextDueDefaultsKey) as? Double {
      nextDue = Date(timeIntervalSince1970: timestamp)
    } else {
      nextDue = nil
    }

    router.actionHandler = { [weak self] actionIdentifier, completion in
      Task { @MainActor [weak self] in
        await self?.handleNotificationAction(actionIdentifier)
        completion()
      }
    }
    router.presentationHandler = { [weak self] _, completion in
      Task { @MainActor [weak self] in
        if self?.isWorkoutActive == true {
          completion([])
        } else {
          completion([.banner, .list, .sound])
        }
      }
    }
    notificationCenter.delegate = router
    registerNotificationCategory()
  }

  /// Call once during app startup. A future persisted snooze/due date is restored;
  /// stale dates are replaced from the current schedule.
  func activate(settings: AppSettings, now: Date = Date()) async {
    activeSettings = settings
    _ = await requestAuthorization()

    if let persistedDue = nextDue,
      persistedDue > now,
      settings.pauseUntil.map({ persistedDue > $0 }) ?? true
    {
      await replacePendingNotification(dueAt: persistedDue, settings: settings, now: now)
    } else {
      await settingsDidChange(settings, now: now)
    }
  }

  @discardableResult
  func requestAuthorization() async -> Bool {
    registerNotificationCategory()
    let granted: Bool
    do {
      granted = try await withCheckedThrowingContinuation { continuation in
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { granted, error in
          if let error {
            continuation.resume(throwing: error)
          } else {
            continuation.resume(returning: granted)
          }
        }
      }
      lastErrorDescription = nil
    } catch {
      granted = false
      lastErrorDescription = error.localizedDescription
    }
    await refreshAuthorizationStatus()
    return granted
  }

  func refreshAuthorizationStatus() async {
    let settings: UNNotificationSettings = await withCheckedContinuation { continuation in
      notificationCenter.getNotificationSettings { settings in
        continuation.resume(returning: settings)
      }
    }
    authorizationStatus = settings.authorizationStatus
  }

  /// Repairs an expired or externally removed notification and keeps the
  /// recurring cadence alive when the menu-bar app wakes or becomes active.
  func refreshIfNeeded(settings: AppSettings, now: Date = Date()) async {
    activeSettings = settings
    await refreshAuthorizationStatus()

    guard !isWorkoutActive else {
      cancelNextReminder()
      return
    }

    if let nextDue, nextDue > now, await hasPendingReminder() {
      armRollover(after: nextDue)
      return
    }
    await settingsDidChange(settings, now: now)
  }

  func settingsDidChange(_ settings: AppSettings, now: Date = Date()) async {
    activeSettings = settings
    guard !isWorkoutActive else {
      cancelNextReminder()
      return
    }
    let due = nextScheduledDate(after: now, settings: settings)
    await replacePendingNotification(dueAt: due, settings: settings, now: now)
  }

  func workoutCompleted(at completionDate: Date = Date(), settings: AppSettings) async {
    isWorkoutActive = false
    activeSettings = settings
    let due = nextScheduledDate(after: completionDate, settings: settings)
    await replacePendingNotification(dueAt: due, settings: settings, now: completionDate)
  }

  /// Re-enters the normal cadence when a started workout is closed without a saved session.
  func workoutDismissed(at date: Date = Date(), settings: AppSettings) async {
    isWorkoutActive = false
    activeSettings = settings
    let due = nextScheduledDate(after: date, settings: settings)
    await replacePendingNotification(dueAt: due, settings: settings, now: date)
  }

  func snoozeTenMinutes(from date: Date = Date(), settings: AppSettings) async {
    activeSettings = settings

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
    let due = nextScheduledDate(after: now, settings: pausedSettings)
    await replacePendingNotification(dueAt: due, settings: pausedSettings, now: now)
  }

  func cancelNextReminder() {
    scheduleRevision &+= 1
    rolloverTask?.cancel()
    rolloverTask = nil
    notificationCenter.removePendingNotificationRequests(
      withIdentifiers: [ReminderNotificationIdentifier.request]
    )
    setPersistedNextDue(nil)
    lastErrorDescription = nil
  }

  func workoutStarted() {
    isWorkoutActive = true
    cancelNextReminder()
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
    notificationCenter.setNotificationCategories([category])
  }

  private func handleNotificationAction(_ actionIdentifier: String) async {
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
    notificationCenter.removePendingNotificationRequests(
      withIdentifiers: [ReminderNotificationIdentifier.request]
    )

    guard !isWorkoutActive else {
      rolloverTask?.cancel()
      rolloverTask = nil
      setPersistedNextDue(nil)
      lastErrorDescription = nil
      return
    }

    guard let due else {
      rolloverTask?.cancel()
      rolloverTask = nil
      setPersistedNextDue(nil)
      lastErrorDescription = nil
      return
    }

    let content = UNMutableNotificationContent()
    content.title = "该活动一下颈肩了"
    content.body = "用 2–3 分钟完成一次颈肩微运动。"
    content.categoryIdentifier = ReminderNotificationIdentifier.category
    content.threadIdentifier = "cn.eigenlogic.mellowdesk.reminders"
    if settings.soundEnabled {
      content.sound = .default
    }

    let trigger = UNTimeIntervalNotificationTrigger(
      timeInterval: max(1, due.timeIntervalSince(now)),
      repeats: false
    )
    let request = UNNotificationRequest(
      identifier: ReminderNotificationIdentifier.request,
      content: content,
      trigger: trigger
    )

    do {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        notificationCenter.add(request) { error in
          if let error {
            continuation.resume(throwing: error)
          } else {
            continuation.resume(returning: ())
          }
        }
      }
      guard revision == scheduleRevision, !isWorkoutActive else {
        if isWorkoutActive {
          notificationCenter.removePendingNotificationRequests(
            withIdentifiers: [ReminderNotificationIdentifier.request]
          )
          setPersistedNextDue(nil)
        }
        return
      }
      setPersistedNextDue(due)
      armRollover(after: due)
      lastErrorDescription = nil
    } catch {
      rolloverTask?.cancel()
      rolloverTask = nil
      setPersistedNextDue(nil)
      lastErrorDescription = error.localizedDescription
    }
  }

  private func hasPendingReminder() async -> Bool {
    let requests: [UNNotificationRequest] = await withCheckedContinuation { continuation in
      notificationCenter.getPendingNotificationRequests { requests in
        continuation.resume(returning: requests)
      }
    }
    return requests.contains { $0.identifier == ReminderNotificationIdentifier.request }
  }

  private func armRollover(after due: Date) {
    rolloverTask?.cancel()
    let delay = max(1, due.timeIntervalSinceNow + 1)
    let maximumDelay = 14.0 * 24 * 60 * 60
    let nanoseconds = UInt64(min(delay, maximumDelay) * 1_000_000_000)

    rolloverTask = Task { @MainActor [weak self] in
      do {
        try await Task.sleep(nanoseconds: nanoseconds)
      } catch {
        return
      }
      guard let self, !Task.isCancelled else { return }
      let settings = self.resolvedSettings()
      await self.settingsDidChange(settings, now: Date())
    }
  }

  private func setPersistedNextDue(_ date: Date?) {
    nextDue = date
    if let date {
      defaults.set(date.timeIntervalSince1970, forKey: Self.nextDueDefaultsKey)
    } else {
      defaults.removeObject(forKey: Self.nextDueDefaultsKey)
    }
  }

}
