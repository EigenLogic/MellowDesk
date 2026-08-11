import Foundation

public struct ReminderSchedule: Codable, Equatable, Sendable {
  /// Calendar weekday values use Foundation's convention: 1 is Sunday and 7 is Saturday.
  public let intervalMinutes: Int
  public let workdayWeekdays: Set<Int>
  public let workStartMinutes: Int
  public let workEndMinutes: Int

  public init(
    intervalMinutes: Int,
    workdayWeekdays: Set<Int>,
    workStartMinutes: Int,
    workEndMinutes: Int
  ) {
    self.intervalMinutes = intervalMinutes
    self.workdayWeekdays = workdayWeekdays
    self.workStartMinutes = workStartMinutes
    self.workEndMinutes = workEndMinutes
  }

  public static let standard = ReminderSchedule(
    intervalMinutes: 60,
    workdayWeekdays: Set(2...6),
    workStartMinutes: 9 * 60,
    workEndMinutes: 18 * 60
  )

  public var isValid: Bool {
    intervalMinutes > 0
      && !workdayWeekdays.isEmpty
      && workdayWeekdays.allSatisfy { (1...7).contains($0) }
      && (0..<24 * 60).contains(workStartMinutes)
      && (1...24 * 60).contains(workEndMinutes)
      && workStartMinutes < workEndMinutes
  }

  /// If `date` is outside an enabled work window, returns the beginning of the next window.
  /// Otherwise adds the configured interval and moves an after-hours result to the next window.
  public func nextReminder(after date: Date, calendar: Calendar = .current) -> Date? {
    guard isValid else { return nil }
    guard let inWindowReference = adjustedToWorkWindow(date, calendar: calendar) else {
      return nil
    }
    if inWindowReference != date {
      return inWindowReference
    }
    guard let candidate = calendar.date(byAdding: .minute, value: intervalMinutes, to: date) else {
      return nil
    }
    return adjustedToWorkWindow(candidate, calendar: calendar)
  }

  /// Keeps a snooze target if it is already inside a work window; otherwise moves it to
  /// the beginning of the next enabled window. It doesn't add the regular interval.
  public func adjustedToWorkWindow(_ date: Date, calendar: Calendar = .current) -> Date? {
    guard isValid else { return nil }

    let referenceDay = calendar.startOfDay(for: date)
    for dayOffset in 0...14 {
      guard let day = calendar.date(byAdding: .day, value: dayOffset, to: referenceDay),
        let weekday = calendar.dateComponents([.weekday], from: day).weekday,
        workdayWeekdays.contains(weekday),
        let workStart = calendar.date(byAdding: .minute, value: workStartMinutes, to: day),
        let workEnd = calendar.date(byAdding: .minute, value: workEndMinutes, to: day)
      else {
        continue
      }
      if dayOffset == 0, date >= workStart, date < workEnd {
        return date
      }
      if date < workStart || dayOffset > 0 {
        return workStart
      }
    }
    return nil
  }
}
