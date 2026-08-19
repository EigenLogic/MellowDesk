import Foundation
import MellowDeskCore
import XCTest

@testable import MellowDesk

@MainActor
final class ActivityHistoryStoreTests: XCTestCase {
  func testAppendPersistsQuickActivitiesInChronologicalOrder() throws {
    let context = try makeContext()
    defer { context.remove() }
    let later = ActivityCompletion(
      activity: .water,
      completedAt: Date(timeIntervalSince1970: 200)
    )
    let earlier = ActivityCompletion(
      activity: .stand,
      completedAt: Date(timeIntervalSince1970: 100)
    )
    let store = ActivityHistoryStore(fileURL: context.fileURL)

    try store.append(later)
    try store.append(earlier)

    XCTAssertEqual(store.completions, [earlier, later])
    XCTAssertEqual(store.recent(), [later, earlier])
    XCTAssertEqual(
      ActivityHistoryStore(fileURL: context.fileURL).completions,
      [earlier, later]
    )
  }

  func testPelvicFloorCompletionPersistsAndReloads() throws {
    let context = try makeContext()
    defer { context.remove() }
    let completion = ActivityCompletion(
      activity: .pelvicFloor,
      completedAt: Date(timeIntervalSince1970: 300),
      sourceID: "pelvic-reminder"
    )
    let store = ActivityHistoryStore(fileURL: context.fileURL)

    try store.append(completion)

    XCTAssertEqual(store.completions, [completion])
    XCTAssertEqual(ActivityHistoryStore(fileURL: context.fileURL).completions, [completion])
  }

  func testAppendWithSameIdentifierReplacesExistingCompletion() throws {
    let context = try makeContext()
    defer { context.remove() }
    let id = UUID()
    let store = ActivityHistoryStore(fileURL: context.fileURL)
    try store.append(
      ActivityCompletion(
        id: id,
        activity: .water,
        completedAt: Date(timeIntervalSince1970: 100)
      )
    )
    let replacement = ActivityCompletion(
      id: id,
      activity: .stand,
      completedAt: Date(timeIntervalSince1970: 200)
    )

    try store.append(replacement)

    XCTAssertEqual(store.completions, [replacement])
  }

  func testAppendWithSameSourceIdentifierIsIdempotent() throws {
    let context = try makeContext()
    defer { context.remove() }
    let store = ActivityHistoryStore(fileURL: context.fileURL)
    try store.append(
      ActivityCompletion(
        activity: .water,
        completedAt: Date(timeIntervalSince1970: 100),
        sourceID: "reminder-42"
      )
    )
    let replacement = ActivityCompletion(
      activity: .water,
      completedAt: Date(timeIntervalSince1970: 101),
      sourceID: "reminder-42"
    )

    try store.append(replacement)

    XCTAssertEqual(store.completions, [replacement])
  }

  func testNeckExerciseIsRejectedAndRemainsOwnedByWorkoutHistory() throws {
    let context = try makeContext()
    defer { context.remove() }
    let store = ActivityHistoryStore(fileURL: context.fileURL)
    let completion = ActivityCompletion(
      activity: .neck,
      completedAt: Date(timeIntervalSince1970: 100)
    )

    XCTAssertThrowsError(try store.append(completion)) { error in
      XCTAssertEqual(
        error as? ActivityHistoryStore.StoreError,
        .unsupportedActivity(.neck)
      )
    }
    XCTAssertTrue(store.completions.isEmpty)
    XCTAssertFalse(FileManager.default.fileExists(atPath: context.fileURL.path))
  }

  func testDayQueryUsesHalfOpenCalendarDay() throws {
    let context = try makeContext()
    defer { context.remove() }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let day = date(2030, 1, 2, 12, calendar: calendar)
    let store = ActivityHistoryStore(fileURL: context.fileURL)
    let previous = ActivityCompletion(
      activity: .water,
      completedAt: date(2030, 1, 1, 23, calendar: calendar)
    )
    let first = ActivityCompletion(
      activity: .stand,
      completedAt: date(2030, 1, 2, 0, calendar: calendar)
    )
    let second = ActivityCompletion(
      activity: .water,
      completedAt: date(2030, 1, 2, 23, calendar: calendar)
    )
    let next = ActivityCompletion(
      activity: .stand,
      completedAt: date(2030, 1, 3, 0, calendar: calendar)
    )
    for completion in [previous, first, second, next] {
      try store.append(completion)
    }

    XCTAssertEqual(store.completions(on: day, calendar: calendar), [first, second])
  }

  func testCorruptFileIsBackedUpAndReset() throws {
    let context = try makeContext()
    defer { context.remove() }
    try FileManager.default.createDirectory(
      at: context.fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data("not-json".utf8).write(to: context.fileURL)

    let store = ActivityHistoryStore(fileURL: context.fileURL)

    XCTAssertTrue(store.completions.isEmpty)
    XCTAssertNotNil(store.lastErrorDescription)
    let backupURL = try XCTUnwrap(store.lastRecoveryBackupURL)
    XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: context.fileURL.path))
  }

  private func makeContext() throws -> ActivityHistoryTestContext {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("mellowdesk-activity-history-tests-\(UUID().uuidString)")
    return ActivityHistoryTestContext(
      directory: directory,
      fileURL: directory.appendingPathComponent(ActivityHistoryStore.fileName)
    )
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

private struct ActivityHistoryTestContext {
  let directory: URL
  let fileURL: URL

  func remove() {
    try? FileManager.default.removeItem(at: directory)
  }
}
