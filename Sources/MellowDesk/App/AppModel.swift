import AppKit
import Combine
import Foundation
import MellowDeskCore

@MainActor
final class AppModel: ObservableObject {
  static let shared = AppModel()

  let settingsStore: SettingsStore
  let historyStore: HistoryStore
  let reminderScheduler: ReminderScheduler
  let launchAtLoginService: LaunchAtLoginService

  @Published private(set) var lastUserFacingError: String?

  private var cancellables: Set<AnyCancellable> = []
  private var didStart = false

  init(
    settingsStore: SettingsStore? = nil,
    historyStore: HistoryStore? = nil,
    reminderScheduler: ReminderScheduler? = nil,
    launchAtLoginService: LaunchAtLoginService? = nil
  ) {
    self.settingsStore = settingsStore ?? SettingsStore()
    self.historyStore = historyStore ?? HistoryStore()
    self.reminderScheduler = reminderScheduler ?? ReminderScheduler()
    self.launchAtLoginService = launchAtLoginService ?? LaunchAtLoginService()

    self.settingsStore.objectWillChange
      .merge(with: self.historyStore.objectWillChange)
      .merge(with: self.reminderScheduler.objectWillChange)
      .merge(with: self.launchAtLoginService.objectWillChange)
      .sink { [weak self] _ in self?.objectWillChange.send() }
      .store(in: &cancellables)
  }

  var settings: AppSettings { settingsStore.settings }
  var nextDue: Date? { reminderScheduler.nextDue }
  var activeReminder: ReminderOccurrence? { reminderScheduler.activeReminder }

  var todayCompletedCount: Int {
    completedSessions(on: Date()).count
  }

  var lastCompletedAt: Date? {
    historyStore.sessions
      .filter { $0.status == .completed }
      .compactMap(\.endedAt)
      .max()
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

    NotificationCenter.default.publisher(for: .mellowDeskStartWorkoutRequested)
      .receive(on: RunLoop.main)
      .sink { _ in
        AppWindowCoordinator.shared.showWorkout()
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
    guard activeReminder?.id == id else { return false }
    AppWindowCoordinator.shared.showWorkoutFromReminder()
    guard reminderScheduler.workoutStarted(reminderID: id) else { return false }
    return true
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
    Task {
      await reminderScheduler.workoutCompleted(
        at: completionDate,
        settings: settings
      )
    }

    do {
      try historyStore.append(session)
      lastUserFacingError = nil
      return true
    } catch {
      lastUserFacingError = "训练已完成，但记录保存失败：\(error.localizedDescription)"
      return false
    }
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
      lastUserFacingError = nil
    } catch {
      lastUserFacingError = "无法清除历史记录：\(error.localizedDescription)"
    }
  }

  func dismissError() {
    lastUserFacingError = nil
  }

  func dailyCompletions(days: Int, endingAt date: Date = Date()) -> [DailyCompletion] {
    guard days > 0 else { return [] }
    let calendar = Calendar.current
    let endDay = calendar.startOfDay(for: date)
    return (0..<days).reversed().compactMap { offset in
      guard let day = calendar.date(byAdding: .day, value: -offset, to: endDay) else {
        return nil
      }
      return DailyCompletion(
        date: day,
        count: completedSessions(on: day, calendar: calendar).count
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

    if completedSessions(on: cursor, calendar: calendar).isEmpty,
      let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor)
    {
      cursor = yesterday
    }

    while !completedSessions(on: cursor, calendar: calendar).isEmpty {
      count += 1
      guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else {
        break
      }
      cursor = previous
    }
    return count
  }

  private func completedSessions(
    on day: Date,
    calendar: Calendar = .current
  ) -> [WorkoutSession] {
    historyStore.sessions(on: day, calendar: calendar).filter {
      $0.status == .completed
    }
  }
}
