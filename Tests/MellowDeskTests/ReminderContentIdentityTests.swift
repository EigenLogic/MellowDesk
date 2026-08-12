import XCTest

@testable import MellowDesk

final class ReminderContentIdentityTests: XCTestCase {
  func testContentIsRebuiltForANewOccurrenceButNotRepeatedShows() {
    var identity = ReminderContentIdentity()

    XCTAssertTrue(identity.shouldRender("first"))
    XCTAssertFalse(identity.shouldRender("first"))
    XCTAssertTrue(identity.shouldRender("second"))
    XCTAssertFalse(identity.shouldRender("second"))
  }
}
