import XCTest

@testable import MellowDeskCore

final class WellnessPlanTests: XCTestCase {
  func testStandardPlanUsesStandWaterNeckRotation() {
    XCTAssertEqual(WellnessPlan.cycleLength, 3)
    XCTAssertEqual(WellnessPlan.activity(for: 0), .stand)
    XCTAssertEqual(WellnessPlan.activity(for: 1), .water)
    XCTAssertEqual(WellnessPlan.activity(for: 2), .neck)
  }

  func testCycleIndexWrapsAcrossPositiveAndNegativeValues() {
    XCTAssertEqual(WellnessPlan.normalizedSlot(0), 0)
    XCTAssertEqual(WellnessPlan.normalizedSlot(2), 2)
    XCTAssertEqual(WellnessPlan.normalizedSlot(3), 0)
    XCTAssertEqual(WellnessPlan.normalizedSlot(7), 1)
    XCTAssertEqual(WellnessPlan.normalizedSlot(-1), 2)
    XCTAssertEqual(WellnessPlan.normalizedSlot(-3), 0)
  }

  func testActivityLookupUsesNormalizedCycleIndex() {
    XCTAssertEqual(WellnessPlan.activity(for: 0), .stand)
    XCTAssertEqual(WellnessPlan.activity(for: 1), .water)
    XCTAssertEqual(WellnessPlan.activity(for: 2), .neck)
    XCTAssertEqual(WellnessPlan.activity(for: 3), .stand)
    XCTAssertEqual(WellnessPlan.activity(for: -1), .neck)
  }

  func testOnlyWaterAndStandAreQuickActivities() {
    XCTAssertTrue(WellnessActivityKind.stand.isQuickActivity)
    XCTAssertTrue(WellnessActivityKind.water.isQuickActivity)
    XCTAssertFalse(WellnessActivityKind.neck.isQuickActivity)
  }

  func testActivityCompletionRoundTripsThroughJSON() throws {
    let completion = ActivityCompletion(
      id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
      activity: .water,
      completedAt: Date(timeIntervalSince1970: 1_800_000_000),
      sourceID: "reminder-42"
    )

    let data = try JSONEncoder().encode(completion)
    let decoded = try JSONDecoder().decode(ActivityCompletion.self, from: data)

    XCTAssertEqual(decoded, completion)
  }
}
