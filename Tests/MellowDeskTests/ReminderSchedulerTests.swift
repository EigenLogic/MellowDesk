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

  func testLegacyDueOnlyActiveOccurrenceDecodesAsNeckSlot() async throws {
    let context = makeContext()
    defer { context.clearDefaults() }
    let now = date(2030, 8, 12, 10, 0)
    let due = now.addingTimeInterval(-30)
    let legacyData = try JSONEncoder().encode(["dueAt": due])
    context.defaults.set(legacyData, forKey: ReminderScheduler.activeReminderDefaultsKey)
    let scheduler = context.makeScheduler()

    await scheduler.activate(settings: settings, now: now)

    let occurrence = try XCTUnwrap(scheduler.activeReminder)
    XCTAssertEqual(occurrence.dueAt, due)
    XCTAssertEqual(occurrence.slot, 2)
    XCTAssertEqual(occurrence.activity, .neck)
    XCTAssertEqual(scheduler.nextActivity, .neck)
    XCTAssertEqual(
      context.defaults.integer(forKey: ReminderScheduler.nextSlotDefaultsKey),
      2
    )
  }

  func testBrandNewScheduleStartsWithStandAndUsesStandNotificationCopy() async throws {
    let context = makeContext()
    defer { context.clearDefaults() }
    let now = date(2030, 8, 12, 10, 0)
    let scheduler = context.makeScheduler()

    await scheduler.settingsDidChange(settings, now: now)

    let due = now.addingTimeInterval(50 * 60)
    let occurrence = ReminderOccurrence(dueAt: due, slot: 0)
    let request = try XCTUnwrap(context.client.requests[occurrence.notificationRequestIdentifier])
    XCTAssertEqual(scheduler.nextDue, due)
    XCTAssertEqual(scheduler.nextActivity, .stand)
    XCTAssertEqual(request.content.title, "起来走两步吧")
    XCTAssertEqual(request.content.body, "离开椅子活动 2 分钟，轻松走动就算完成。")
  }

  func testSnoozePreservesCurrentActivitySlot() async throws {
    let context = makeContext()
    defer { context.clearDefaults() }
    let now = date(2030, 8, 12, 10, 0)
    let due = now.addingTimeInterval(-30)
    context.defaults.set(due.timeIntervalSince1970, forKey: ReminderScheduler.nextDueDefaultsKey)
    context.defaults.set(1, forKey: ReminderScheduler.nextSlotDefaultsKey)
    context.defaults.set(
      due.timeIntervalSince1970,
      forKey: ReminderScheduler.nextSlotDueDefaultsKey
    )
    let scheduler = context.makeScheduler()
    await scheduler.activate(settings: settings, now: now)
    XCTAssertEqual(scheduler.activeReminder?.activity, .water)

    await scheduler.snoozeTenMinutes(from: now, settings: settings)

    let snoozedDue = now.addingTimeInterval(10 * 60)
    let occurrence = ReminderOccurrence(dueAt: snoozedDue, slot: 1)
    let request = try XCTUnwrap(context.client.requests[occurrence.notificationRequestIdentifier])
    XCTAssertNil(scheduler.activeReminder)
    XCTAssertEqual(scheduler.nextDue, snoozedDue)
    XCTAssertEqual(scheduler.nextActivity, .water)
    XCTAssertEqual(request.content.title, "要不要喝几口水？")
    XCTAssertEqual(
      context.defaults.integer(forKey: ReminderScheduler.nextSlotDefaultsKey),
      1
    )
  }

  func testStandCompletionAdvancesToWaterAndPersistsAcrossRecreation() async throws {
    let context = makeContext()
    defer { context.clearDefaults() }
    let now = date(2030, 8, 12, 10, 0)
    let due = now.addingTimeInterval(50 * 60)
    let scheduler = context.makeScheduler()
    await scheduler.settingsDidChange(settings, now: now)
    await scheduler.reconcileDue(settings: settings, now: due)
    let standReminder = try XCTUnwrap(scheduler.activeReminder)
    XCTAssertEqual(standReminder.activity, .stand)
    XCTAssertTrue(scheduler.activityStarted(reminderID: standReminder.id))

    let completedAt = due.addingTimeInterval(2 * 60)
    await scheduler.activityCompleted(at: completedAt, settings: settings)

    let nextDue = completedAt.addingTimeInterval(50 * 60)
    XCTAssertEqual(scheduler.nextDue, nextDue)
    XCTAssertEqual(scheduler.nextActivity, .water)
    XCTAssertEqual(
      context.defaults.integer(forKey: ReminderScheduler.nextSlotDefaultsKey),
      1
    )

    let restoredScheduler = context.makeScheduler()
    await restoredScheduler.activate(settings: settings, now: completedAt)
    XCTAssertEqual(restoredScheduler.nextDue, nextDue)
    XCTAssertEqual(restoredScheduler.nextActivity, .water)
    let occurrence = ReminderOccurrence(dueAt: nextDue, slot: 1)
    let request = try XCTUnwrap(context.client.requests[occurrence.notificationRequestIdentifier])
    XCTAssertEqual(request.content.title, "要不要喝几口水？")
  }

  func testDismissedQuickActivitySnoozesTenMinutesWithoutAdvancingSlot() async throws {
    let context = makeContext()
    defer { context.clearDefaults() }
    let now = date(2030, 8, 12, 10, 0)
    let due = now.addingTimeInterval(50 * 60)
    let scheduler = context.makeScheduler()
    await scheduler.settingsDidChange(settings, now: now)
    await scheduler.reconcileDue(settings: settings, now: due)
    let standReminder = try XCTUnwrap(scheduler.activeReminder)
    XCTAssertEqual(standReminder.activity, .stand)
    XCTAssertTrue(scheduler.activityStarted(reminderID: standReminder.id))

    await scheduler.activityDismissed(
      at: due,
      settings: settings,
      snoozeMinutes: 10
    )

    let snoozedDue = due.addingTimeInterval(10 * 60)
    XCTAssertEqual(scheduler.nextDue, snoozedDue)
    XCTAssertEqual(scheduler.nextActivity, .stand)
    XCTAssertEqual(
      context.defaults.integer(forKey: ReminderScheduler.nextSlotDefaultsKey),
      0
    )
    let occurrence = ReminderOccurrence(dueAt: snoozedDue, slot: 0)
    XCTAssertNotNil(context.client.requests[occurrence.notificationRequestIdentifier])
  }

  func testSkippedActivityAdvancesRotationWithoutRecordingCompletion() async throws {
    let context = makeContext()
    defer { context.clearDefaults() }
    let now = date(2030, 8, 12, 10, 0)
    let due = now.addingTimeInterval(50 * 60)
    let scheduler = context.makeScheduler()
    await scheduler.settingsDidChange(settings, now: now)
    await scheduler.reconcileDue(settings: settings, now: due)
    let standReminder = try XCTUnwrap(scheduler.activeReminder)
    XCTAssertTrue(scheduler.activityStarted(reminderID: standReminder.id))

    await scheduler.activityDismissed(
      at: due,
      settings: settings,
      advanceRotation: true
    )

    XCTAssertEqual(scheduler.nextActivity, .water)
    XCTAssertEqual(scheduler.nextDue, due.addingTimeInterval(50 * 60))
    XCTAssertEqual(
      context.defaults.integer(forKey: ReminderScheduler.nextSlotDefaultsKey),
      1
    )
  }

  func testDismissedQuickActivitySchedulesAfterAnActivePause() async throws {
    let context = makeContext()
    defer { context.clearDefaults() }
    let now = date(2030, 8, 12, 10, 0)
    let due = now.addingTimeInterval(50 * 60)
    let scheduler = context.makeScheduler()
    await scheduler.settingsDidChange(settings, now: now)
    await scheduler.reconcileDue(settings: settings, now: due)
    let standReminder = try XCTUnwrap(scheduler.activeReminder)
    XCTAssertEqual(standReminder.activity, .stand)
    XCTAssertTrue(scheduler.activityStarted(reminderID: standReminder.id))

    let pauseUntil = date(2030, 8, 13, 0, 0)
    var pausedSettings = settings
    pausedSettings.pauseUntil = pauseUntil
    await scheduler.pause(until: pauseUntil, settings: pausedSettings, now: due)
    XCTAssertNil(scheduler.nextDue)

    let dismissedAt = due.addingTimeInterval(60)
    await scheduler.activityDismissed(
      at: dismissedAt,
      settings: pausedSettings,
      snoozeMinutes: 10
    )

    let expectedDue = pausedSettings.reminderSchedule.nextReminder(
      after: pauseUntil,
      calendar: utcCalendar
    )
    let unwrappedExpectedDue = try XCTUnwrap(expectedDue)
    XCTAssertEqual(scheduler.nextDue, unwrappedExpectedDue)
    XCTAssertGreaterThan(scheduler.nextDue ?? .distantPast, pauseUntil)
    XCTAssertEqual(scheduler.nextActivity, .stand)
    let occurrence = ReminderOccurrence(dueAt: unwrappedExpectedDue, slot: 0)
    XCTAssertNotNil(context.client.requests[occurrence.notificationRequestIdentifier])
  }

  func testManualActivityCompletionDoesNotAdvanceActiveStandReminder() async throws {
    let context = makeContext()
    defer { context.clearDefaults() }
    let now = date(2030, 8, 12, 10, 0)
    let due = now.addingTimeInterval(-30)
    context.defaults.set(due.timeIntervalSince1970, forKey: ReminderScheduler.nextDueDefaultsKey)
    context.defaults.set(0, forKey: ReminderScheduler.nextSlotDefaultsKey)
    context.defaults.set(
      due.timeIntervalSince1970,
      forKey: ReminderScheduler.nextSlotDueDefaultsKey
    )
    let scheduler = context.makeScheduler()
    await scheduler.activate(settings: settings, now: now)
    XCTAssertEqual(try XCTUnwrap(scheduler.activeReminder).activity, .stand)

    scheduler.activityStarted()
    let completedAt = now.addingTimeInterval(2 * 60)
    let nextDue = scheduler.recordActivityCompletion(at: completedAt, settings: settings)

    let expectedDue = completedAt.addingTimeInterval(50 * 60)
    XCTAssertEqual(nextDue, expectedDue)
    XCTAssertEqual(scheduler.nextDue, expectedDue)
    XCTAssertEqual(scheduler.nextActivity, .stand)
    XCTAssertEqual(
      context.defaults.integer(forKey: ReminderScheduler.nextSlotDefaultsKey),
      0
    )
  }

  func testRecordedCompletionIsImmediatelyRestoredAsNextSlotWithoutAwaiting() async throws {
    let context = makeContext()
    defer { context.clearDefaults() }
    let now = date(2030, 8, 12, 10, 0)
    let due = now.addingTimeInterval(50 * 60)
    let scheduler = context.makeScheduler()
    await scheduler.settingsDidChange(settings, now: now)
    await scheduler.reconcileDue(settings: settings, now: due)
    let standReminder = try XCTUnwrap(scheduler.activeReminder)
    XCTAssertEqual(standReminder.activity, .stand)
    XCTAssertTrue(scheduler.activityStarted(reminderID: standReminder.id))

    let completedAt = due.addingTimeInterval(2 * 60)
    let persistedDue = scheduler.recordActivityCompletion(at: completedAt, settings: settings)
    let restoredScheduler = context.makeScheduler()

    let expectedDue = completedAt.addingTimeInterval(50 * 60)
    XCTAssertEqual(persistedDue, expectedDue)
    XCTAssertEqual(restoredScheduler.nextDue, expectedDue)
    XCTAssertEqual(restoredScheduler.nextActivity, .water)
    XCTAssertEqual(
      context.defaults.integer(forKey: ReminderScheduler.nextSlotDefaultsKey),
      1
    )
    XCTAssertEqual(
      context.defaults.double(forKey: ReminderScheduler.nextSlotDueDefaultsKey),
      expectedDue.timeIntervalSince1970,
      accuracy: 0.001
    )
  }

  func testMismatchedSlotDueMigratesPersistedScheduleAsLegacyNeckReminder() async throws {
    let context = makeContext()
    defer { context.clearDefaults() }
    let now = date(2030, 8, 12, 10, 0)
    let due = now.addingTimeInterval(50 * 60)
    let staleSlotDue = now.addingTimeInterval(40 * 60)
    context.defaults.set(due.timeIntervalSince1970, forKey: ReminderScheduler.nextDueDefaultsKey)
    context.defaults.set(1, forKey: ReminderScheduler.nextSlotDefaultsKey)
    context.defaults.set(
      staleSlotDue.timeIntervalSince1970,
      forKey: ReminderScheduler.nextSlotDueDefaultsKey
    )
    let scheduler = context.makeScheduler()

    XCTAssertEqual(scheduler.nextDue, due)
    XCTAssertEqual(scheduler.nextActivity, .neck)
    await scheduler.activate(settings: settings, now: now)

    let occurrence = ReminderOccurrence(dueAt: due, slot: 2)
    let request = try XCTUnwrap(context.client.requests[occurrence.notificationRequestIdentifier])
    XCTAssertEqual(request.content.title, "给颈肩 3 分钟")
    XCTAssertEqual(
      context.defaults.integer(forKey: ReminderScheduler.nextSlotDefaultsKey),
      2
    )
    XCTAssertEqual(
      context.defaults.double(forKey: ReminderScheduler.nextSlotDueDefaultsKey),
      due.timeIntervalSince1970,
      accuracy: 0.001
    )
  }

  func testSystemPrimaryActionPostsGenericRequestWithoutPreclearingActiveReminder() async throws {
    let context = makeContext()
    defer { context.clearDefaults() }
    let now = date(2030, 8, 12, 10, 0)
    let due = now.addingTimeInterval(-30)
    context.defaults.set(due.timeIntervalSince1970, forKey: ReminderScheduler.nextDueDefaultsKey)
    context.defaults.set(0, forKey: ReminderScheduler.nextSlotDefaultsKey)
    context.defaults.set(
      due.timeIntervalSince1970,
      forKey: ReminderScheduler.nextSlotDueDefaultsKey
    )
    let scheduler = context.makeScheduler()
    await scheduler.activate(settings: settings, now: now)
    let occurrence = try XCTUnwrap(scheduler.activeReminder)
    var requestedReminderID: ReminderOccurrence.ID?
    let token = NotificationCenter.default.addObserver(
      forName: .mellowDeskStartActivityRequested,
      object: nil,
      queue: nil
    ) { notification in
      requestedReminderID = notification.object as? ReminderOccurrence.ID
    }
    defer { NotificationCenter.default.removeObserver(token) }

    await scheduler.handleNotificationAction(
      ReminderNotificationIdentifier.startWorkoutAction,
      requestIdentifier: occurrence.notificationRequestIdentifier
    )

    XCTAssertEqual(requestedReminderID, occurrence.id)
    XCTAssertEqual(scheduler.activeReminder, occurrence)
    XCTAssertEqual(scheduler.nextDue, due)
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

  func testLateSameDueAddsKeepOneFallbackWithoutRecursiveReplay() async throws {
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

    for _ in 0..<100 where context.client.heldAddCount < 1 {
      await Task.yield()
    }
    XCTAssertEqual(context.client.heldAddCount, 1)
    XCTAssertEqual(context.client.heldAddIdentifier, identifier)

    context.client.holdNextAdd = true
    let refresh = Task {
      await scheduler.refreshIfNeeded(settings: settings, now: now.addingTimeInterval(1))
    }
    for _ in 0..<100 where context.client.heldAddCount < 2 {
      await Task.yield()
    }
    XCTAssertEqual(context.client.heldAddCount, 2)

    await scheduler.refreshIfNeeded(settings: settings, now: now.addingTimeInterval(2))
    XCTAssertNotNil(context.client.requests[identifier])

    context.client.completeAllHeldAdds()
    await activation.value
    await refresh.value

    XCTAssertNotNil(context.client.requests[identifier])
    XCTAssertEqual(scheduler.nextDue, due)
    XCTAssertEqual(context.client.addedIdentifiers.filter { $0 == identifier }.count, 3)
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
  private var heldAddIdentifiers: [String] = []
  private var heldAddContinuations: [CheckedContinuation<Void, Error>] = []
  private(set) var delegate: (any UNUserNotificationCenterDelegate)?
  private(set) var categories: Set<UNNotificationCategory> = []

  var heldAddIdentifier: String? { heldAddIdentifiers.last }
  var heldAddCount: Int { heldAddContinuations.count }

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
      heldAddIdentifiers.append(request.identifier)
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        heldAddContinuations.append(continuation)
      }
    }
    requests[request.identifier] = request
  }

  func completeHeldAdd() {
    guard !heldAddContinuations.isEmpty else { return }
    let continuation = heldAddContinuations.removeFirst()
    heldAddIdentifiers.removeFirst()
    continuation.resume(returning: ())
  }

  func completeAllHeldAdds() {
    let continuations = heldAddContinuations
    heldAddContinuations.removeAll()
    heldAddIdentifiers.removeAll()
    for continuation in continuations {
      continuation.resume(returning: ())
    }
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
