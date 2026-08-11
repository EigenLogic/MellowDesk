import XCTest

@testable import MellowDeskCore

final class WorkoutStatisticsTests: XCTestCase {
  func testTodaySevenAndThirtyDayStatisticsUseHalfOpenCalendarWindows() {
    let calendar = utcCalendar()
    let reference = date(2026, 8, 11, 12, calendar: calendar)
    let sessions = [
      session(on: date(2026, 8, 11, 10, calendar: calendar), status: .completed, completed: 10),
      session(on: date(2026, 8, 10, 10, calendar: calendar), status: .completed, completed: 8),
      session(on: date(2026, 8, 3, 10, calendar: calendar), status: .skipped, completed: 0),
      session(on: date(2026, 7, 13, 10, calendar: calendar), status: .cancelled, completed: 2),
      WorkoutSession(
        startedAt: date(2026, 8, 11, 11, calendar: calendar),
        endedAt: nil,
        status: .inProgress,
        routineVersion: ExercisePlan.v1.routineVersion,
        results: [],
        usedCamera: true
      ),
    ]

    let statistics = WorkoutStatisticsCalculator.recent(
      sessions: sessions,
      referenceDate: reference,
      calendar: calendar
    )

    XCTAssertEqual(statistics.today.recordedSessions, 1)
    XCTAssertEqual(statistics.today.completedSessions, 1)
    XCTAssertEqual(statistics.today.completedRepetitions, 10)

    XCTAssertEqual(statistics.last7Days.recordedSessions, 2)
    XCTAssertEqual(statistics.last7Days.completedSessions, 2)
    XCTAssertEqual(statistics.last7Days.activeDays, 2)
    XCTAssertEqual(statistics.last7Days.repetitionCompletionRate, 0.9, accuracy: 0.0001)

    XCTAssertEqual(statistics.last30Days.recordedSessions, 4)
    XCTAssertEqual(statistics.last30Days.completedSessions, 2)
    XCTAssertEqual(statistics.last30Days.completedRepetitions, 20)
    XCTAssertEqual(statistics.last30Days.targetRepetitions, 40)
  }

  private func session(
    on date: Date,
    status: WorkoutSessionStatus,
    completed: Int
  ) -> WorkoutSession {
    WorkoutSession(
      startedAt: date.addingTimeInterval(-300),
      endedAt: date,
      status: status,
      routineVersion: ExercisePlan.v1.routineVersion,
      results: [
        ExerciseResult(
          exerciseID: .gentleNod,
          targetReps: 10,
          completedReps: completed,
          mode: .camera
        )
      ],
      usedCamera: true
    )
  }

  private func utcCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }

  private func date(
    _ year: Int,
    _ month: Int,
    _ day: Int,
    _ hour: Int,
    calendar: Calendar
  ) -> Date {
    calendar.date(
      from: DateComponents(
        year: year,
        month: month,
        day: day,
        hour: hour
      ))!
  }
}
