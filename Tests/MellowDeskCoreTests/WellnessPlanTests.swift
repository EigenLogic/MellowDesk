import XCTest

@testable import MellowDeskCore

final class WellnessPlanTests: XCTestCase {
  func testStandardPlanUsesFourActivityRotation() {
    XCTAssertEqual(WellnessPlan.cycleLength, 4)
    XCTAssertEqual(WellnessPlan.activity(for: 0), .stand)
    XCTAssertEqual(WellnessPlan.activity(for: 1), .water)
    XCTAssertEqual(WellnessPlan.activity(for: 2), .neck)
    XCTAssertEqual(WellnessPlan.activity(for: 3), .pelvicFloor)
  }

  func testCycleIndexWrapsAcrossPositiveAndNegativeValues() {
    XCTAssertEqual(WellnessPlan.normalizedSlot(0), 0)
    XCTAssertEqual(WellnessPlan.normalizedSlot(2), 2)
    XCTAssertEqual(WellnessPlan.normalizedSlot(4), 0)
    XCTAssertEqual(WellnessPlan.normalizedSlot(9), 1)
    XCTAssertEqual(WellnessPlan.normalizedSlot(-1), 3)
    XCTAssertEqual(WellnessPlan.normalizedSlot(-4), 0)
  }

  func testActivityLookupUsesNormalizedCycleIndex() {
    XCTAssertEqual(WellnessPlan.activity(for: 0), .stand)
    XCTAssertEqual(WellnessPlan.activity(for: 1), .water)
    XCTAssertEqual(WellnessPlan.activity(for: 2), .neck)
    XCTAssertEqual(WellnessPlan.activity(for: 3), .pelvicFloor)
    XCTAssertEqual(WellnessPlan.activity(for: 4), .stand)
    XCTAssertEqual(WellnessPlan.activity(for: -1), .pelvicFloor)
  }

  func testOnlyWaterAndStandAreQuickActivities() {
    XCTAssertTrue(WellnessActivityKind.stand.isQuickActivity)
    XCTAssertTrue(WellnessActivityKind.water.isQuickActivity)
    XCTAssertFalse(WellnessActivityKind.neck.isQuickActivity)
    XCTAssertFalse(WellnessActivityKind.pelvicFloor.isQuickActivity)
    XCTAssertTrue(WellnessActivityKind.pelvicFloor.usesLightweightHistory)
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
