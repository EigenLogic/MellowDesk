import XCTest

@testable import MellowDeskCore

final class ReminderScheduleTests: XCTestCase {
  private let schedule = ReminderSchedule(
    intervalMinutes: 60,
    workdayWeekdays: Set(2...6),
    workStartMinutes: 9 * 60,
    workEndMinutes: 18 * 60
  )

  func testBeforeWorkStartsReturnsSameDayWorkStart() {
    let calendar = utcCalendar()
    let mondayMorning = date(2026, 8, 10, 8, 30, calendar: calendar)

    XCTAssertEqual(
      schedule.nextReminder(after: mondayMorning, calendar: calendar),
      date(2026, 8, 10, 9, 0, calendar: calendar)
    )
  }

  func testInsideWorkWindowReturnsOneFullIntervalLater() {
    let calendar = utcCalendar()
    let exactStart = date(2026, 8, 10, 9, 0, calendar: calendar)

    XCTAssertEqual(
      schedule.nextReminder(after: exactStart, calendar: calendar),
      date(2026, 8, 10, 10, 0, calendar: calendar)
    )
  }

  func testEndOfDayAndWeekendRollToNextWorkday() {
    let calendar = utcCalendar()

    XCTAssertEqual(
      schedule.nextReminder(
        after: date(2026, 8, 14, 17, 30, calendar: calendar),
        calendar: calendar
      ),
      date(2026, 8, 17, 9, 0, calendar: calendar)
    )
    XCTAssertEqual(
      schedule.nextReminder(
        after: date(2026, 8, 15, 12, 0, calendar: calendar),
        calendar: calendar
      ),
      date(2026, 8, 17, 9, 0, calendar: calendar)
    )
  }

  func testSnoozeAdjustmentPreservesInWindowTimeAndMovesAfterHours() {
    let calendar = utcCalendar()
    let inWindow = date(2026, 8, 10, 17, 50, calendar: calendar)
    let afterHours = date(2026, 8, 10, 18, 5, calendar: calendar)

    XCTAssertEqual(schedule.adjustedToWorkWindow(inWindow, calendar: calendar), inWindow)
    XCTAssertEqual(
      schedule.adjustedToWorkWindow(afterHours, calendar: calendar),
      date(2026, 8, 11, 9, 0, calendar: calendar)
    )
  }

  func testInvalidScheduleReturnsNil() {
    let invalid = ReminderSchedule(
      intervalMinutes: 0,
      workdayWeekdays: [],
      workStartMinutes: 18 * 60,
      workEndMinutes: 9 * 60
    )
    XCTAssertFalse(invalid.isValid)
    XCTAssertNil(invalid.nextReminder(after: Date(), calendar: utcCalendar()))
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
    _ minute: Int,
    calendar: Calendar
  ) -> Date {
    calendar.date(
      from: DateComponents(
        year: year,
        month: month,
        day: day,
        hour: hour,
        minute: minute
      ))!
  }
}
