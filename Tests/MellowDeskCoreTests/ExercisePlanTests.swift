import XCTest

@testable import MellowDeskCore

final class ExercisePlanTests: XCTestCase {
  func testV1RoutineHasVersionedProfessionalExerciseSet() {
    let plan = ExercisePlan.v1

    XCTAssertEqual(plan.routineVersion, "neck-ease-v1.0")
    XCTAssertEqual(plan.exercises.map(\.kind), [.neckRotation, .lateralFlexion, .gentleNod])
    XCTAssertTrue(plan.safetyNotice.contains("立即停止"))

    let rotation = plan.exercises[0]
    XCTAssertEqual(rotation.directions, [.left, .right])
    XCTAssertEqual(rotation.repetitionsPerDirection, 4)
    XCTAssertEqual(rotation.targetRepetitions, 8)

    let flexion = plan.exercises[1]
    XCTAssertEqual(flexion.directions, [.left, .right])
    XCTAssertEqual(flexion.repetitionsPerDirection, 3)
    XCTAssertEqual(flexion.targetRepetitions, 6)

    let nod = plan.exercises[2]
    XCTAssertEqual(nod.directions, [.down])
    XCTAssertEqual(nod.repetitionsPerDirection, 5)
    XCTAssertEqual(nod.targetRepetitions, 5)
    XCTAssertTrue(nod.safetyBoundary.contains("不包含向后仰头"))
  }

  func testGentleNodRecognitionTargetAdaptsWithinFiveToEightDegrees() {
    let plan = ExercisePlan.v1
    let rotation = plan.exercises[0]
    let nod = plan.exercises[2]

    XCTAssertEqual(nod.recognitionTargetDegrees(observedPeakDegrees: 5.5), 5, accuracy: 0.0001)
    XCTAssertEqual(nod.recognitionTargetDegrees(observedPeakDegrees: 10), 6, accuracy: 0.0001)
    XCTAssertEqual(nod.recognitionTargetDegrees(observedPeakDegrees: 20), 8, accuracy: 0.0001)
    XCTAssertEqual(
      rotation.recognitionTargetDegrees(observedPeakDegrees: 8),
      rotation.defaultTargetDegrees,
      accuracy: 0.0001
    )
  }
}
