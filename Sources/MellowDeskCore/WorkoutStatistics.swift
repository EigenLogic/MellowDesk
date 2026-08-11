import Foundation

public struct WorkoutPeriodStatistics: Codable, Equatable, Sendable {
  public let startDate: Date
  public let endDate: Date
  public let recordedSessions: Int
  public let completedSessions: Int
  public let activeDays: Int
  public let targetRepetitions: Int
  public let completedRepetitions: Int

  public init(
    startDate: Date,
    endDate: Date,
    recordedSessions: Int,
    completedSessions: Int,
    activeDays: Int,
    targetRepetitions: Int,
    completedRepetitions: Int
  ) {
    self.startDate = startDate
    self.endDate = endDate
    self.recordedSessions = max(0, recordedSessions)
    self.completedSessions = max(0, completedSessions)
    self.activeDays = max(0, activeDays)
    self.targetRepetitions = max(0, targetRepetitions)
    self.completedRepetitions = max(0, completedRepetitions)
  }

  public var sessionCompletionRate: Double {
    guard recordedSessions > 0 else { return 0 }
    return min(Double(completedSessions) / Double(recordedSessions), 1)
  }

  public var repetitionCompletionRate: Double {
    guard targetRepetitions > 0 else { return 0 }
    return min(Double(completedRepetitions) / Double(targetRepetitions), 1)
  }
}

public struct RecentWorkoutStatistics: Codable, Equatable, Sendable {
  public let today: WorkoutPeriodStatistics
  public let last7Days: WorkoutPeriodStatistics
  public let last30Days: WorkoutPeriodStatistics

  public init(
    today: WorkoutPeriodStatistics,
    last7Days: WorkoutPeriodStatistics,
    last30Days: WorkoutPeriodStatistics
  ) {
    self.today = today
    self.last7Days = last7Days
    self.last30Days = last30Days
  }
}

public enum WorkoutStatisticsCalculator {
  public static func recent(
    sessions: [WorkoutSession],
    referenceDate: Date,
    calendar: Calendar = .current
  ) -> RecentWorkoutStatistics {
    let todayStart = calendar.startOfDay(for: referenceDate)
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? referenceDate
    let sevenDayStart = calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
    let thirtyDayStart = calendar.date(byAdding: .day, value: -29, to: todayStart) ?? todayStart

    return RecentWorkoutStatistics(
      today: summarize(sessions: sessions, from: todayStart, to: tomorrow, calendar: calendar),
      last7Days: summarize(
        sessions: sessions, from: sevenDayStart, to: tomorrow, calendar: calendar),
      last30Days: summarize(
        sessions: sessions, from: thirtyDayStart, to: tomorrow, calendar: calendar)
    )
  }

  public static func summarize(
    sessions: [WorkoutSession],
    from startDate: Date,
    to endDate: Date,
    calendar: Calendar = .current
  ) -> WorkoutPeriodStatistics {
    let included = sessions.filter { session in
      guard session.status != .inProgress else { return false }
      let eventDate = session.endedAt ?? session.startedAt
      return eventDate >= startDate && eventDate < endDate
    }

    let completed = included.filter { $0.status == .completed }
    let activeDaySet = Set(
      completed.map { session in
        calendar.startOfDay(for: session.endedAt ?? session.startedAt)
      })

    return WorkoutPeriodStatistics(
      startDate: startDate,
      endDate: endDate,
      recordedSessions: included.count,
      completedSessions: completed.count,
      activeDays: activeDaySet.count,
      targetRepetitions: included.reduce(0) { $0 + $1.targetRepetitions },
      completedRepetitions: included.reduce(0) { $0 + $1.completedRepetitions }
    )
  }
}
