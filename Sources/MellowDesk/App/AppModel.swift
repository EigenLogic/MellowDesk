import AppKit
import Combine
import Foundation
import MellowDeskCore

@MainActor
final class AppModel: ObservableObject {
  static let shared = AppModel()

  let settingsStore: SettingsStore
  let historyStore: HistoryStore
  let activityHistoryStore: ActivityHistoryStore
  let reminderScheduler: ReminderScheduler
  let launchAtLoginService: LaunchAtLoginService

  @Published private(set) var lastUserFacingError: String?

  private var cancellables: Set<AnyCancellable> = []
  private var didStart = false

  init(
    settingsStore: SettingsStore? = nil,
    historyStore: HistoryStore? = nil,
    activityHistoryStore: ActivityHistoryStore? = nil,
    reminderScheduler: ReminderScheduler? = nil,
    launchAtLoginService: LaunchAtLoginService? = nil
  ) {
    self.settingsStore = settingsStore ?? SettingsStore()
    self.historyStore = historyStore ?? HistoryStore()
    self.activityHistoryStore = activityHistoryStore ?? ActivityHistoryStore()
    self.reminderScheduler = reminderScheduler ?? ReminderScheduler()
    self.launchAtLoginService = launchAtLoginService ?? LaunchAtLoginService()

    self.settingsStore.objectWillChange
      .merge(with: self.historyStore.objectWillChange)
      .merge(with: self.activityHistoryStore.objectWillChange)
      .merge(with: self.reminderScheduler.objectWillChange)
      .merge(with: self.launchAtLoginService.objectWillChange)
      .sink { [weak self] _ in self?.objectWillChange.send() }
      .store(in: &cancellables)
  }

  var settings: AppSettings { settingsStore.settings }
  var nextDue: Date? { reminderScheduler.nextDue }
  var activeReminder: ReminderOccurrence? { reminderScheduler.activeReminder }

  var todayCompletedCount: Int {
    todayCount(for: .neck) + todayCount(for: .water) + todayCount(for: .stand)
  }

  var lastCompletedAt: Date? {
    let neckCompletion = historyStore.sessions
      .filter { $0.status == .completed }
      .compactMap(\.endedAt)
      .max()
    let quickCompletion = activityHistoryStore.completions.map(\.completedAt).max()
    return [neckCompletion, quickCompletion].compactMap { $0 }.max()
  }

  func start() {
    guard !didStart else { return }
    didStart = true

    launchAtLoginService.refresh()
    reminderScheduler.$activeReminder
      .removeDuplicates()
      .sink { occurrence in
        AppWindowCoordinator.shared.syncReminder(occurrence)
      }
      .store(in: &cancellables)

    NotificationCenter.default.publisher(for: .mellowDeskStartActivityRequested)
      .receive(on: RunLoop.main)
      .sink { [weak self] notification in
        guard let reminderID = notification.object as? ReminderOccurrence.ID else { return }
        _ = self?.startCurrentReminder(id: reminderID)
      }
      .store(in: &cancellables)

    Task {
      await reminderScheduler.activate(settings: settings)
    }

    let firstLaunchKey = "cn.eigenlogic.mellowdesk.did-present-first-launch.v1"
    if !UserDefaults.standard.bool(forKey: firstLaunchKey) {
      UserDefaults.standard.set(true, forKey: firstLaunchKey)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
        AppWindowCoordinator.shared.showDashboard()
      }
    }
  }

  func applicationDidBecomeActive() {
    launchAtLoginService.refresh()
    Task {
      await reminderScheduler.refreshIfNeeded(settings: settings)
    }
  }

  func updateSettings(_ update: (inout AppSettings) -> Void) {
    settingsStore.update(update)
    Task {
      await reminderScheduler.settingsDidChange(settingsStore.settings)
    }
  }

  func setLaunchAtLogin(_ enabled: Bool) {
    Task {
      let accepted = await launchAtLoginService.setEnabled(enabled)
      if accepted {
        settingsStore.update { $0.launchAtLoginEnabled = enabled }
      } else {
        lastUserFacingError =
          launchAtLoginService.lastErrorDescription
          ?? "无法更新登录启动设置。"
      }
    }
  }

  func snoozeTenMinutes() {
    Task {
      await reminderScheduler.snoozeTenMinutes(settings: settings)
    }
  }

  @discardableResult
  func startCurrentReminder(id: ReminderOccurrence.ID) -> Bool {
    guard let occurrence = activeReminder, occurrence.id == id else { return false }
    switch occurrence.activity {
    case .neck:
      AppWindowCoordinator.shared.showWorkoutFromReminder()
    case .stand, .water:
      AppWindowCoordinator.shared.showMovementBreakFromReminder(occurrence)
    }
    guard reminderScheduler.activityStarted(reminderID: id) else { return false }
    return true
  }

  func recordWaterNow() {
    saveQuickCompletion(activity: .water, at: Date(), sourceID: nil)
  }

  func startManualMovementBreak() {
    reminderScheduler.activityStarted()
    AppWindowCoordinator.shared.showManualMovementBreak()
  }

  func completeQuickActivity(
    _ activity: WellnessActivityKind,
    sourceID: String?,
    at completionDate: Date = Date()
  ) {
    saveQuickCompletion(activity: activity, at: completionDate, sourceID: sourceID)
    reminderScheduler.recordActivityCompletion(at: completionDate, settings: settings)
    Task {
      await reminderScheduler.reconcileDue(settings: settings, now: completionDate)
    }
  }

  func quickActivityDismissed(fromReminder: Bool) {
    Task {
      await reminderScheduler.activityDismissed(
        settings: settings,
        snoozeMinutes: fromReminder ? 10 : nil
      )
    }
  }

  func pauseUntilTomorrow() {
    guard
      let tomorrow = Calendar.current.date(
        byAdding: .day,
        value: 1,
        to: Calendar.current.startOfDay(for: Date())
      )
    else { return }
    settingsStore.pause(until: tomorrow)
    Task {
      await reminderScheduler.pause(until: tomorrow, settings: settingsStore.settings)
    }
  }

  func resumeReminders() {
    settingsStore.resume()
    Task {
      await reminderScheduler.settingsDidChange(settingsStore.settings)
    }
  }

  @discardableResult
  func saveCompletedSession(_ session: WorkoutSession) -> Bool {
    let completionDate = session.endedAt ?? Date()
    let didSave: Bool
    do {
      try historyStore.append(session)
      lastUserFacingError = nil
      didSave = true
    } catch {
      lastUserFacingError = "训练已完成，但记录保存失败：\(error.localizedDescription)"
      didSave = false
    }
    reminderScheduler.recordActivityCompletion(at: completionDate, settings: settings)
    Task {
      await reminderScheduler.reconcileDue(settings: settings, now: completionDate)
    }
    return didSave
  }

  func workoutDismissed() {
    Task {
      await reminderScheduler.workoutDismissed(settings: settings)
    }
  }

  func workoutStarted() {
    reminderScheduler.workoutStarted()
  }

  func clearHistory() {
    do {
      try historyStore.clear()
      try activityHistoryStore.clear()
      lastUserFacingError = nil
    } catch {
      lastUserFacingError = "无法清除历史记录：\(error.localizedDescription)"
    }
  }

  func dismissError() {
    lastUserFacingError = nil
  }

  func dailyCompletions(days: Int, endingAt date: Date = Date()) -> [DailyCompletion] {
    dailyCompletions(days: days, activity: nil, endingAt: date)
  }

  func dailyCompletions(
    days: Int,
    activity: WellnessActivityKind?,
    endingAt date: Date = Date()
  ) -> [DailyCompletion] {
    guard days > 0 else { return [] }
    let calendar = Calendar.current
    let endDay = calendar.startOfDay(for: date)
    return (0..<days).reversed().compactMap { offset in
      guard let day = calendar.date(byAdding: .day, value: -offset, to: endDay) else {
        return nil
      }
      return DailyCompletion(
        date: day,
        count: completionCount(on: day, activity: activity, calendar: calendar)
      )
    }
  }

  func completedCount(inLastDays days: Int) -> Int {
    dailyCompletions(days: days).reduce(0) { $0 + $1.count }
  }

  var currentStreak: Int {
    let calendar = Calendar.current
    var cursor = calendar.startOfDay(for: Date())
    var count = 0

    if completionCount(on: cursor, activity: nil, calendar: calendar) == 0,
      let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor)
    {
      cursor = yesterday
    }

    while completionCount(on: cursor, activity: nil, calendar: calendar) > 0 {
      count += 1
      guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else {
        break
      }
      cursor = previous
    }
    return count
  }

  func todayCount(for activity: WellnessActivityKind) -> Int {
    completionCount(on: Date(), activity: activity, calendar: .current)
  }

  func recentWellnessItems(limit: Int = 8) -> [WellnessHistoryItem] {
    let workouts: [WellnessHistoryItem] = historyStore.recentCompleted(limit: limit).compactMap {
      session in
      guard let completedAt = session.endedAt else { return nil }
      let duration = AppFormatters.duration(
        seconds: completedAt.timeIntervalSince(session.startedAt)
      )
      return WellnessHistoryItem(
        id: "workout-\(session.id.uuidString)",
        activity: .neck,
        completedAt: completedAt,
        detail: "用时 \(duration)"
      )
    }
    let quick = activityHistoryStore.recent(limit: limit).map { completion in
      WellnessHistoryItem(
        id: "activity-\(completion.id.uuidString)",
        activity: completion.activity,
        completedAt: completion.completedAt,
        detail: completion.activity == .water ? "按自己的节奏补水" : "完成 2 分钟活动"
      )
    }
    return Array((workouts + quick).sorted { $0.completedAt > $1.completedAt }.prefix(limit))
  }

  private func completedSessions(
    on day: Date,
    calendar: Calendar = .current
  ) -> [WorkoutSession] {
    historyStore.sessions(on: day, calendar: calendar).filter {
      $0.status == .completed
    }
  }

  private func completionCount(
    on day: Date,
    activity: WellnessActivityKind?,
    calendar: Calendar
  ) -> Int {
    switch activity {
    case .neck:
      return completedSessions(on: day, calendar: calendar).count
    case .stand, .water:
      return activityHistoryStore.completions(on: day, calendar: calendar)
        .filter { $0.activity == activity }
        .count
    case nil:
      return completedSessions(on: day, calendar: calendar).count
        + activityHistoryStore.completions(on: day, calendar: calendar).count
    }
  }

  private func saveQuickCompletion(
    activity: WellnessActivityKind,
    at completionDate: Date,
    sourceID: String?
  ) {
    do {
      try activityHistoryStore.append(
        ActivityCompletion(
          activity: activity,
          completedAt: completionDate,
          sourceID: sourceID
        )
      )
      lastUserFacingError = nil
    } catch {
      lastUserFacingError = "活动已完成，但记录保存失败：\(error.localizedDescription)"
    }
  }
}
