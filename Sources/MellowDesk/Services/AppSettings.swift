import Foundation
import MellowDeskCore

/// User-configurable reminder and completion preferences.
///
/// Calendar weekdays use Foundation's convention: Sunday is 1 and Saturday is 7.
struct AppSettings: Codable, Equatable, Sendable {
  static let defaultReminderIntervalMinutes = 50
  static let defaultWorkdayWeekdays: Set<Int> = [2, 3, 4, 5, 6]
  static let defaultWorkStartMinutes = 9 * 60
  static let defaultWorkEndMinutes = 18 * 60
  static let defaultDailyWorkoutGoal = 3
  static let defaultPelvicFloorTrainingEnabled = true

  var reminderIntervalMinutes: Int
  var workdayWeekdays: Set<Int>
  var workStartMinutes: Int
  var workEndMinutes: Int
  var soundEnabled: Bool
  var launchAtLoginEnabled: Bool
  var pauseUntil: Date?
  var dailyWorkoutGoal: Int
  /// Optional pelvic-floor follow-along. It is available by default but never
  /// joins the reminder rotation.
  var pelvicFloorTrainingEnabled: Bool

  static let `default` = AppSettings()

  init(
    reminderIntervalMinutes: Int = defaultReminderIntervalMinutes,
    workdayWeekdays: Set<Int> = defaultWorkdayWeekdays,
    workStartMinutes: Int = defaultWorkStartMinutes,
    workEndMinutes: Int = defaultWorkEndMinutes,
    soundEnabled: Bool = true,
    launchAtLoginEnabled: Bool = false,
    pauseUntil: Date? = nil,
    dailyWorkoutGoal: Int = defaultDailyWorkoutGoal,
    pelvicFloorTrainingEnabled: Bool = defaultPelvicFloorTrainingEnabled
  ) {
    self.reminderIntervalMinutes = reminderIntervalMinutes
    self.workdayWeekdays = workdayWeekdays
    self.workStartMinutes = workStartMinutes
    self.workEndMinutes = workEndMinutes
    self.soundEnabled = soundEnabled
    self.launchAtLoginEnabled = launchAtLoginEnabled
    self.pauseUntil = pauseUntil
    self.dailyWorkoutGoal = dailyWorkoutGoal
    self.pelvicFloorTrainingEnabled = pelvicFloorTrainingEnabled
    normalize()
  }

  var reminderSchedule: ReminderSchedule {
    ReminderSchedule(
      intervalMinutes: reminderIntervalMinutes,
      workdayWeekdays: workdayWeekdays,
      workStartMinutes: workStartMinutes,
      workEndMinutes: workEndMinutes
    )
  }

  var isPaused: Bool {
    guard let pauseUntil else { return false }
    return pauseUntil > Date()
  }

  mutating func normalize() {
    reminderIntervalMinutes = min(max(reminderIntervalMinutes, 15), 180)

    let validWeekdays = workdayWeekdays.filter { (1...7).contains($0) }
    workdayWeekdays =
      validWeekdays.isEmpty
      ? Self.defaultWorkdayWeekdays
      : Set(validWeekdays)

    workStartMinutes = min(max(workStartMinutes, 0), 23 * 60 + 59)
    workEndMinutes = min(max(workEndMinutes, 1), 24 * 60)
    if workEndMinutes <= workStartMinutes {
      workStartMinutes = Self.defaultWorkStartMinutes
      workEndMinutes = Self.defaultWorkEndMinutes
    }

    dailyWorkoutGoal = min(max(dailyWorkoutGoal, 1), 12)
  }

  private enum CodingKeys: String, CodingKey {
    case reminderIntervalMinutes
    case workdayWeekdays
    case workStartMinutes
    case workEndMinutes
    case soundEnabled
    case launchAtLoginEnabled
    case pauseUntil
    case dailyWorkoutGoal
    case pelvicFloorTrainingEnabled
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    reminderIntervalMinutes =
      try container.decodeIfPresent(
        Int.self,
        forKey: .reminderIntervalMinutes
      ) ?? Self.defaultReminderIntervalMinutes
    workdayWeekdays =
      try container.decodeIfPresent(
        Set<Int>.self,
        forKey: .workdayWeekdays
      ) ?? Self.defaultWorkdayWeekdays
    workStartMinutes =
      try container.decodeIfPresent(
        Int.self,
        forKey: .workStartMinutes
      ) ?? Self.defaultWorkStartMinutes
    workEndMinutes =
      try container.decodeIfPresent(
        Int.self,
        forKey: .workEndMinutes
      ) ?? Self.defaultWorkEndMinutes
    soundEnabled = try container.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? true
    launchAtLoginEnabled =
      try container.decodeIfPresent(
        Bool.self,
        forKey: .launchAtLoginEnabled
      ) ?? false
    pauseUntil = try container.decodeIfPresent(Date.self, forKey: .pauseUntil)
    dailyWorkoutGoal =
      try container.decodeIfPresent(
        Int.self,
        forKey: .dailyWorkoutGoal
      ) ?? Self.defaultDailyWorkoutGoal
    pelvicFloorTrainingEnabled =
      try container.decodeIfPresent(
        Bool.self,
        forKey: .pelvicFloorTrainingEnabled
      ) ?? Self.defaultPelvicFloorTrainingEnabled
    normalize()
  }
}
