import UserNotifications
import XCTest

@testable import MellowDesk

@MainActor
final class ReminderSchedulerTests: XCTestCase {
  func testOverdueReminderBecomesDurableOccurrenceAndDoesNotAdvance() async {
    let context = makeContext()
    defer { context.clearDefaults() }
    let now = date(2030, 8, 12, 10, 0)
    let due = date(2030, 8, 12, 9, 50)
    context.defaults.set(due.timeIntervalSince1970, forKey: ReminderScheduler.nextDueDefaultsKey)
    let scheduler = context.makeScheduler()

    await scheduler.activate(settings: settings, now: now)

    XCTAssertEqual(scheduler.activeReminder, ReminderOccurrence(dueAt: due))
    XCTAssertEqual(scheduler.nextDue, due)
    XCTAssertTrue(context.client.requests.isEmpty)

    await scheduler.reconcileDue(settings: settings, now: now.addingTimeInterval(60))
    XCTAssertEqual(scheduler.activeReminder, ReminderOccurrence(dueAt: due))
    XCTAssertEqual(scheduler.nextDue, due)
  }

  func testDueReconcileCancelsFallbackAndCreatesOnlyOneOccurrence() async throws {
    let context = makeContext()
    defer { context.clearDefaults() }
    let now = date(2030, 8, 12, 10, 0)
    let due = now.addingTimeInterval(50 * 60)
    context.defaults.set(due.timeIntervalSince1970, forKey: ReminderScheduler.nextDueDefaultsKey)
    let scheduler = context.makeScheduler()

    await scheduler.activate(settings: settings, now: now)

    let occurrence = ReminderOccurrence(dueAt: due)
    let request = try XCTUnwrap(context.client.requests[occurrence.notificationRequestIdentifier])
    let trigger = try XCTUnwrap(request.trigger as? UNTimeIntervalNotificationTrigger)
    XCTAssertEqual(trigger.timeInterval, 50 * 60 + 5, accuracy: 0.001)

    await scheduler.reconcileDue(settings: settings, now: due)
    await scheduler.reconcileDue(settings: settings, now: due.addingTimeInterval(1))

    XCTAssertEqual(scheduler.activeReminder, occurrence)
    XCTAssertNil(context.client.requests[occurrence.notificationRequestIdentifier])
  }

  func testSnoozeClearsOccurrenceAndSchedulesTenMinutesFromResponse() async {
    let context = makeContext()
    defer { context.clearDefaults() }
    let now = date(2030, 8, 12, 10, 0)
    let due = now.addingTimeInterval(-30)
    context.defaults.set(due.timeIntervalSince1970, forKey: ReminderScheduler.nextDueDefaultsKey)
    let scheduler = context.makeScheduler()
    await scheduler.activate(settings: settings, now: now)
    let activeIdentifier = ReminderOccurrence(dueAt: due).notificationRequestIdentifier

    await scheduler.snoozeTenMinutes(from: now, settings: settings)

    let snoozedDue = now.addingTimeInterval(10 * 60)
    XCTAssertNil(scheduler.activeReminder)
    XCTAssertEqual(scheduler.nextDue, snoozedDue)
    XCTAssertTrue(context.client.removedDeliveredIdentifiers.contains(activeIdentifier))
    XCTAssertNotNil(
      context.client.requests[
        ReminderOccurrence(dueAt: snoozedDue).notificationRequestIdentifier
      ]
    )
  }

  func testInAppDueStillWorksWhenSystemNotificationAddFails() async {
    let context = makeContext()
    defer { context.clearDefaults() }
    let now = date(2030, 8, 12, 10, 0)
    let due = now.addingTimeInterval(50 * 60)
    context.defaults.set(due.timeIntervalSince1970, forKey: ReminderScheduler.nextDueDefaultsKey)
    context.client.addError = TestNotificationError.addFailed
    let scheduler = context.makeScheduler()

    await scheduler.activate(settings: settings, now: now)
    XCTAssertEqual(scheduler.nextDue, due)
    XCTAssertNotNil(scheduler.lastErrorDescription)

    await scheduler.reconcileDue(settings: settings, now: due)
    XCTAssertEqual(scheduler.activeReminder, ReminderOccurrence(dueAt: due))
  }

  func testActiveOccurrenceSurvivesSchedulerRecreation() async {
    let context = makeContext()
    defer { context.clearDefaults() }
    let now = date(2030, 8, 12, 10, 0)
    let due = now.addingTimeInterval(-30)
    context.defaults.set(due.timeIntervalSince1970, forKey: ReminderScheduler.nextDueDefaultsKey)
    let firstScheduler = context.makeScheduler()
    await firstScheduler.activate(settings: settings, now: now)

    let restoredScheduler = context.makeScheduler()
    await restoredScheduler.activate(settings: settings, now: now.addingTimeInterval(60))

    XCTAssertEqual(restoredScheduler.activeReminder, ReminderOccurrence(dueAt: due))
    XCTAssertEqual(restoredScheduler.nextDue, due)
  }

  func testSettingsChangeDoesNotDismissActiveOccurrence() async {
    let context = makeContext()
    defer { context.clearDefaults() }
    let now = date(2030, 8, 12, 10, 0)
    let due = now.addingTimeInterval(-30)
    context.defaults.set(due.timeIntervalSince1970, forKey: ReminderScheduler.nextDueDefaultsKey)
    let scheduler = context.makeScheduler()
    await scheduler.activate(settings: settings, now: now)

    var changedSettings = settings
    changedSettings.reminderIntervalMinutes = 90
    changedSettings.soundEnabled = false
    changedSettings.dailyWorkoutGoal = 8
    await scheduler.settingsDidChange(changedSettings, now: now)

    XCTAssertEqual(scheduler.activeReminder, ReminderOccurrence(dueAt: due))
    XCTAssertEqual(scheduler.nextDue, due)
    XCTAssertTrue(context.client.requests.isEmpty)
  }

  func testWorkoutActiveIgnoresSnoozeAndDefersPauseScheduleUntilDismissed() async {
    let context = makeContext()
    defer { context.clearDefaults() }
    let now = date(2030, 8, 12, 10, 0)
    let initialDue = now.addingTimeInterval(50 * 60)
    context.defaults.set(
      initialDue.timeIntervalSince1970,
      forKey: ReminderScheduler.nextDueDefaultsKey
    )
    let scheduler = context.makeScheduler()
    await scheduler.activate(settings: settings, now: now)
    scheduler.workoutStarted()

    await scheduler.snoozeTenMinutes(from: now, settings: settings)
    let pauseUntil = now.addingTimeInterval(24 * 60 * 60)
    var pausedSettings = settings
    pausedSettings.pauseUntil = pauseUntil
    await scheduler.pause(until: pauseUntil, settings: pausedSettings, now: now)

    XCTAssertNil(scheduler.activeReminder)
    XCTAssertNil(scheduler.nextDue)
    XCTAssertTrue(context.client.requests.isEmpty)

    await scheduler.workoutDismissed(at: now, settings: pausedSettings)
    let expectedDue = pausedSettings.reminderSchedule.nextReminder(
      after: pauseUntil,
      calendar: utcCalendar
    )
    XCTAssertEqual(scheduler.nextDue, expectedDue)
  }

  func testWorkoutStartAcceptsOnlyTheCurrentReminderOccurrence() async {
    let context = makeContext()
    defer { context.clearDefaults() }
    let now = date(2030, 8, 12, 10, 0)
    let due = now.addingTimeInterval(-30)
    context.defaults.set(due.timeIntervalSince1970, forKey: ReminderScheduler.nextDueDefaultsKey)
    let scheduler = context.makeScheduler()
    await scheduler.activate(settings: settings, now: now)
    let occurrence = ReminderOccurrence(dueAt: due)

    XCTAssertFalse(scheduler.workoutStarted(reminderID: "stale-reminder"))
    XCTAssertEqual(scheduler.activeReminder, occurrence)
    XCTAssertEqual(scheduler.nextDue, due)

    XCTAssertTrue(scheduler.workoutStarted(reminderID: occurrence.id))
    XCTAssertNil(scheduler.activeReminder)
    XCTAssertNil(scheduler.nextDue)
    XCTAssertFalse(scheduler.workoutStarted(reminderID: occurrence.id))
  }

  func testShutdownPreservesActiveOccurrenceForRelaunch() async {
    let context = makeContext()
    defer { context.clearDefaults() }
    let now = date(2030, 8, 12, 10, 0)
    let due = now.addingTimeInterval(-30)
    context.defaults.set(due.timeIntervalSince1970, forKey: ReminderScheduler.nextDueDefaultsKey)
    let firstScheduler = context.makeScheduler()
    await firstScheduler.activate(settings: settings, now: now)

    firstScheduler.shutdown()
    let relaunchedScheduler = context.makeScheduler()
    await relaunchedScheduler.activate(settings: settings, now: now.addingTimeInterval(60))

    XCTAssertEqual(relaunchedScheduler.activeReminder, ReminderOccurrence(dueAt: due))
    XCTAssertEqual(relaunchedScheduler.nextDue, due)
  }

  func testStaleLegacyAndResolvedOccurrenceActionsAreIgnored() async throws {
    let context = makeContext()
    defer { context.clearDefaults() }
    let now = date(2030, 8, 12, 10, 0)
    let due = now.addingTimeInterval(-30)
    context.defaults.set(due.timeIntervalSince1970, forKey: ReminderScheduler.nextDueDefaultsKey)
    let scheduler = context.makeScheduler()
    await scheduler.activate(settings: settings, now: now)
    let occurrence = ReminderOccurrence(dueAt: due)

    await scheduler.snoozeTenMinutes(from: now, settings: settings)
    let snoozedDue = try XCTUnwrap(scheduler.nextDue)
    await scheduler.handleNotificationAction(
      ReminderNotificationIdentifier.snoozeTenMinutesAction,
      requestIdentifier: ReminderNotificationIdentifier.legacyRequest
    )
    await scheduler.handleNotificationAction(
      ReminderNotificationIdentifier.snoozeTenMinutesAction,
      requestIdentifier: occurrence.notificationRequestIdentifier
    )

    XCTAssertEqual(scheduler.nextDue, snoozedDue)
    XCTAssertNil(scheduler.activeReminder)
    XCTAssertTrue(
      context.client.removedDeliveredIdentifiers.contains(
        ReminderNotificationIdentifier.legacyRequest
      )
    )
  }

  func testLateNotificationAddCannotOverwriteNewerSchedule() async throws {
    let context = makeContext()
    defer { context.clearDefaults() }
    let now = date(2030, 8, 12, 10, 0)
    let firstDue = now.addingTimeInterval(50 * 60)
    context.defaults.set(
      firstDue.timeIntervalSince1970,
      forKey: ReminderScheduler.nextDueDefaultsKey
    )
    context.client.holdNextAdd = true
    let scheduler = context.makeScheduler()
    let activation = Task { await scheduler.activate(settings: settings, now: now) }

    for _ in 0..<100 where context.client.heldAddIdentifier == nil {
      await Task.yield()
    }
    XCTAssertEqual(
      context.client.heldAddIdentifier,
      ReminderOccurrence(dueAt: firstDue).notificationRequestIdentifier
    )

    var changedSettings = settings
    changedSettings.reminderIntervalMinutes = 90
    await scheduler.settingsDidChange(changedSettings, now: now)
    let secondDue = changedSettings.reminderSchedule.nextReminder(
      after: now,
      calendar: utcCalendar
    )
    let unwrappedSecondDue = try XCTUnwrap(secondDue)
    let secondIdentifier = ReminderOccurrence(
      dueAt: unwrappedSecondDue
    ).notificationRequestIdentifier
    XCTAssertNotNil(context.client.requests[secondIdentifier])

    context.client.completeHeldAdd()
    await activation.value

    XCTAssertNil(
      context.client.requests[ReminderOccurrence(dueAt: firstDue).notificationRequestIdentifier]
    )
    XCTAssertNotNil(context.client.requests[secondIdentifier])
    XCTAssertEqual(scheduler.nextDue, secondDue)
  }

  func testLateSameDueAddReplaysCurrentFallbackInsteadOfDeletingIt() async throws {
    let context = makeContext()
    defer { context.clearDefaults() }
    let now = date(2030, 8, 12, 10, 0)
    let due = now.addingTimeInterval(50 * 60)
    let identifier = ReminderOccurrence(dueAt: due).notificationRequestIdentifier
    context.defaults.set(
      due.timeIntervalSince1970,
      forKey: ReminderScheduler.nextDueDefaultsKey
    )
    context.client.holdNextAdd = true
    let scheduler = context.makeScheduler()
    let activation = Task { await scheduler.activate(settings: settings, now: now) }

    for _ in 0..<100 where context.client.heldAddIdentifier == nil {
      await Task.yield()
    }
    XCTAssertEqual(context.client.heldAddIdentifier, identifier)

    await scheduler.refreshIfNeeded(settings: settings, now: now.addingTimeInterval(1))
    XCTAssertNotNil(context.client.requests[identifier])

    context.client.completeHeldAdd()
    await activation.value

    XCTAssertNotNil(context.client.requests[identifier])
    XCTAssertEqual(scheduler.nextDue, due)
    XCTAssertGreaterThanOrEqual(
      context.client.addedIdentifiers.filter { $0 == identifier }.count, 3)
  }

  private var settings: AppSettings {
    AppSettings(
      reminderIntervalMinutes: 50,
      workdayWeekdays: Set(1...7),
      workStartMinutes: 0,
      workEndMinutes: 24 * 60
    )
  }

  private func makeContext() -> ReminderSchedulerTestContext {
    let suiteName = "cn.eigenlogic.mellowdesk.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return ReminderSchedulerTestContext(
      suiteName: suiteName,
      defaults: defaults,
      client: TestReminderNotificationClient()
    )
  }

  private func date(
    _ year: Int,
    _ month: Int,
    _ day: Int,
    _ hour: Int,
    _ minute: Int
  ) -> Date {
    var components = DateComponents()
    components.calendar = utcCalendar
    components.timeZone = utcCalendar.timeZone
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    return components.date!
  }

  private var utcCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }
}

@MainActor
private struct ReminderSchedulerTestContext {
  let suiteName: String
  let defaults: UserDefaults
  let client: TestReminderNotificationClient

  func makeScheduler() -> ReminderScheduler {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return ReminderScheduler(
      notificationClient: client,
      defaults: defaults,
      calendar: calendar
    )
  }

  func clearDefaults() {
    defaults.removePersistentDomain(forName: suiteName)
  }
}

private enum TestNotificationError: Error {
  case addFailed
}

@MainActor
private final class TestReminderNotificationClient: ReminderNotificationClient {
  var requests: [String: UNNotificationRequest] = [:]
  var removedDeliveredIdentifiers: Set<String> = []
  var addError: Error?
  var holdNextAdd = false
  private(set) var addedIdentifiers: [String] = []
  private(set) var heldAddIdentifier: String?
  private var heldAddContinuation: CheckedContinuation<Void, Error>?
  private(set) var delegate: (any UNUserNotificationCenterDelegate)?
  private(set) var categories: Set<UNNotificationCategory> = []

  func setDelegate(_ delegate: (any UNUserNotificationCenterDelegate)?) {
    self.delegate = delegate
  }

  func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
    self.categories = categories
  }

  func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
    true
  }

  func authorizationStatus() async -> UNAuthorizationStatus {
    .authorized
  }

  func add(_ request: UNNotificationRequest) async throws {
    addedIdentifiers.append(request.identifier)
    if let addError { throw addError }
    if holdNextAdd {
      holdNextAdd = false
      heldAddIdentifier = request.identifier
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        heldAddContinuation = continuation
      }
      heldAddIdentifier = nil
    }
    requests[request.identifier] = request
  }

  func completeHeldAdd() {
    let continuation = heldAddContinuation
    heldAddContinuation = nil
    continuation?.resume(returning: ())
  }

  func pendingRequestIdentifiers() async -> Set<String> {
    Set(requests.keys)
  }

  func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
    for identifier in identifiers {
      requests.removeValue(forKey: identifier)
    }
  }

  func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
    removedDeliveredIdentifiers.formUnion(identifiers)
  }
}
