import XCTest

@testable import MellowDeskCore

final class RepCounterTests: XCTestCase {
  private let definition = ExercisePlan.v1.exercises.first { $0.kind == .neckRotation }!
  private let calibration = CalibrationProfile.v1Defaults()
  private let deterministicConfiguration = RepCounterConfiguration(
    minimumTrackingQuality: 0.4,
    maximumInvalidDuration: 0.5,
    maximumSampleGap: 0.5,
    targetReleaseRatio: 0.75,
    filterWindowSize: 1,
    filterAlpha: 1
  )

  func testNormalRepRequiresNeutralTargetHoldAndVisibleReturnHold() {
    var counter = makeCounter()

    XCTAssertEqual(counter.consume(sample(at: 0, yaw: 0)), .none)
    XCTAssertEqual(counter.consume(sample(at: 0.3, yaw: 0)), .stateChanged(.seekingTarget))
    XCTAssertEqual(counter.consume(sample(at: 0.4, yaw: -18)), .stateChanged(.holdingTarget))
    XCTAssertEqual(counter.consume(sample(at: 0.7, yaw: -18)), .stateChanged(.returningToNeutral))
    XCTAssertEqual(counter.consume(sample(at: 0.8, yaw: 0)), .none)
    XCTAssertEqual(counter.consume(sample(at: 1.0, yaw: 0)), .none)
    XCTAssertEqual(
      counter.consume(sample(at: 1.1, yaw: 0)),
      .repCompleted(direction: .left, completedRepetitions: 1)
    )

    XCTAssertEqual(counter.completedRepetitions, 1)
    XCTAssertEqual(counter.completedRepetitionsByDirection[.left], 1)
    XCTAssertEqual(counter.expectedDirection, .right)
    XCTAssertEqual(counter.state, .seekingTarget)
  }

  func testJitterWithinHysteresisDoesNotBreakTargetHold() {
    var counter = makeCounter()
    arm(&counter)

    XCTAssertEqual(counter.consume(sample(at: 0.4, yaw: -16)), .stateChanged(.holdingTarget))
    XCTAssertEqual(counter.consume(sample(at: 0.5, yaw: -13)), .none)
    XCTAssertEqual(counter.consume(sample(at: 0.6, yaw: -16)), .none)
    XCTAssertEqual(counter.consume(sample(at: 0.7, yaw: -14)), .stateChanged(.returningToNeutral))

    _ = counter.consume(sample(at: 0.8, yaw: 3))
    XCTAssertEqual(counter.consume(sample(at: 1.0, yaw: -2)), .none)
    XCTAssertEqual(
      counter.consume(sample(at: 1.1, yaw: -2)),
      .repCompleted(direction: .left, completedRepetitions: 1)
    )
  }

  func testSingleTargetSpikeAndSubthresholdMovementDoNotCount() {
    var counter = makeCounter()
    arm(&counter)

    XCTAssertEqual(counter.consume(sample(at: 0.4, yaw: -18)), .stateChanged(.holdingTarget))
    XCTAssertEqual(counter.consume(sample(at: 0.5, yaw: -5)), .stateChanged(.seekingTarget))

    _ = counter.consume(sample(at: 0.8, yaw: -14))
    _ = counter.consume(sample(at: 1.2, yaw: -14))
    _ = counter.consume(sample(at: 1.5, yaw: 0))

    XCTAssertEqual(counter.completedRepetitions, 0)
    XCTAssertEqual(counter.state, .seekingTarget)
  }

  func testReachedTargetWithoutVisibleNeutralReturnDoesNotCount() {
    var counter = makeCounter()
    arm(&counter)

    _ = counter.consume(sample(at: 0.4, yaw: -18))
    XCTAssertEqual(counter.consume(sample(at: 0.7, yaw: -18)), .stateChanged(.returningToNeutral))
    _ = counter.consume(sample(at: 0.9, yaw: -8))
    _ = counter.consume(sample(at: 1.2, yaw: -7))

    XCTAssertEqual(counter.completedRepetitions, 0)
    XCTAssertEqual(counter.state, .returningToNeutral)
  }

  func testOcclusionLongerThanHalfSecondResetsCurrentRep() {
    var counter = makeCounter()
    arm(&counter)
    _ = counter.consume(sample(at: 0.4, yaw: -18))
    _ = counter.consume(sample(at: 0.7, yaw: -18))
    XCTAssertEqual(counter.state, .returningToNeutral)

    XCTAssertEqual(counter.consume(invalidSample(at: 0.8)), .trackingLost)
    XCTAssertEqual(counter.consume(invalidSample(at: 1.4)), .resetAfterTrackingLoss)
    XCTAssertEqual(counter.state, .awaitingNeutral)

    XCTAssertEqual(counter.consume(sample(at: 1.7, yaw: 0)), .none)
    XCTAssertEqual(counter.state, .awaitingNeutral)
    _ = counter.consume(sample(at: 2.0, yaw: 0))
    XCTAssertEqual(counter.completedRepetitions, 0)
    XCTAssertEqual(counter.state, .seekingTarget)
  }

  func testBriefInvalidFramesNeverContributeToHoldDuration() {
    var counter = makeCounter()
    arm(&counter)
    _ = counter.consume(sample(at: 0.4, yaw: -18))
    _ = counter.consume(sample(at: 0.5, yaw: -18))
    XCTAssertEqual(counter.consume(invalidSample(at: 0.6)), .trackingLost)
    _ = counter.consume(sample(at: 0.7, yaw: -18))

    XCTAssertEqual(counter.state, .holdingTarget)
    XCTAssertEqual(counter.consume(sample(at: 0.9, yaw: -18)), .none)
    XCTAssertEqual(counter.consume(sample(at: 1.0, yaw: -18)), .stateChanged(.returningToNeutral))
  }

  func testBilateralDefinitionAlternatesAndCompletesEachSideQuota() {
    var counter = makeCounter()
    var time: TimeInterval = 0
    _ = counter.consume(sample(at: time, yaw: 0))
    time += 0.3
    _ = counter.consume(sample(at: time, yaw: 0))

    var observedDirections: [MotionDirection] = []
    while !counter.isFinished {
      guard let direction = counter.expectedDirection else {
        XCTFail("Expected a direction before completion")
        break
      }
      observedDirections.append(direction)
      let targetYaw = direction == .left ? -18.0 : 18.0

      time += 0.1
      _ = counter.consume(sample(at: time, yaw: targetYaw))
      time += 0.3
      _ = counter.consume(sample(at: time, yaw: targetYaw))
      time += 0.1
      _ = counter.consume(sample(at: time, yaw: 0))
      time += 0.3
      _ = counter.consume(sample(at: time, yaw: 0))
    }

    XCTAssertEqual(
      observedDirections, [.left, .right, .left, .right, .left, .right, .left, .right])
    XCTAssertEqual(counter.completedRepetitionsByDirection[.left], 4)
    XCTAssertEqual(counter.completedRepetitionsByDirection[.right], 4)
    XCTAssertEqual(counter.completedRepetitions, 8)
    XCTAssertEqual(counter.state, .finished)
  }

  func testOversizedCalibrationNeutralBandCannotMakeTargetPositionNeutral() {
    let broadCalibration = CalibrationProfile(axes: [
      AxisCalibration(
        axis: .yaw,
        neutralDegrees: 0,
        noiseMADDegrees: 5,
        neutralBandDegrees: 20,
        directions: CalibrationProfile.v1Defaults().calibration(for: .yaw)!.directions
      )
    ])
    var counter = RepCounter(
      definition: definition,
      calibration: broadCalibration,
      configuration: deterministicConfiguration
    )
    arm(&counter)
    _ = counter.consume(sample(at: 0.4, yaw: -18))
    _ = counter.consume(sample(at: 0.7, yaw: -18))
    _ = counter.consume(sample(at: 0.8, yaw: -10))
    _ = counter.consume(sample(at: 1.2, yaw: -10))

    XCTAssertEqual(counter.state, .returningToNeutral)
    XCTAssertEqual(counter.completedRepetitions, 0)
  }

  func testInvalidatingCurrentAttemptPreservesCompletedQuota() {
    var counter = makeCounter()
    arm(&counter)
    _ = counter.consume(sample(at: 0.4, yaw: -18))
    _ = counter.consume(sample(at: 0.7, yaw: -18))
    _ = counter.consume(sample(at: 0.8, yaw: 0))
    _ = counter.consume(sample(at: 1.1, yaw: 0))
    XCTAssertEqual(counter.completedRepetitions, 1)

    _ = counter.consume(sample(at: 1.1, yaw: 18))
    counter.invalidateCurrentAttempt()

    XCTAssertEqual(counter.completedRepetitions, 1)
    XCTAssertEqual(counter.expectedDirection, .right)
    XCTAssertEqual(counter.state, .awaitingNeutral)
  }

  func testAdaptiveGentleNodTargetStillRequiresHoldAndReturn() {
    var counter = makeAdaptiveNodCounter(allowsTrackingLoss: false)

    _ = counter.consume(pitchSample(at: 0, pitch: 0))
    _ = counter.consume(pitchSample(at: 0.3, pitch: 0))
    XCTAssertEqual(counter.state, .seekingTarget)
    _ = counter.consume(pitchSample(at: 0.4, pitch: 5))
    _ = counter.consume(pitchSample(at: 0.7, pitch: 5))
    XCTAssertEqual(counter.state, .returningToNeutral)
    _ = counter.consume(pitchSample(at: 0.8, pitch: 0))
    XCTAssertEqual(
      counter.consume(pitchSample(at: 1.1, pitch: 0)),
      .repCompleted(direction: .down, completedRepetitions: 1)
    )
  }

  func testGentleNodCanFinishTargetHoldThroughBriefFaceLossThenRequiresNeutralReturn() {
    var counter = makeAdaptiveNodCounter(allowsTrackingLoss: true)

    _ = counter.consume(pitchSample(at: 0, pitch: 0))
    _ = counter.consume(pitchSample(at: 0.3, pitch: 0))
    _ = counter.consume(pitchSample(at: 0.4, pitch: 5))
    XCTAssertEqual(counter.state, .holdingTarget)
    XCTAssertEqual(counter.consume(invalidSample(at: 0.55)), .trackingLost)
    XCTAssertEqual(counter.consume(invalidSample(at: 0.75)), .trackingLost)
    XCTAssertEqual(counter.state, .holdingTarget)
    XCTAssertEqual(counter.completedRepetitions, 0)
    XCTAssertEqual(
      counter.consume(pitchSample(at: 1.0, pitch: 0)),
      .stateChanged(.returningToNeutral)
    )
    _ = counter.consume(pitchSample(at: 1.1, pitch: 0))
    XCTAssertEqual(
      counter.consume(pitchSample(at: 1.4, pitch: 0)),
      .repCompleted(direction: .down, completedRepetitions: 1)
    )
  }

  func testFaceLossBeforeGentleNodTargetNeverCreatesARepetition() {
    var counter = makeAdaptiveNodCounter(allowsTrackingLoss: true)

    _ = counter.consume(pitchSample(at: 0, pitch: 0))
    _ = counter.consume(pitchSample(at: 0.3, pitch: 0))
    _ = counter.consume(pitchSample(at: 0.4, pitch: 4.9))
    XCTAssertEqual(counter.state, .seekingTarget)
    _ = counter.consume(invalidSample(at: 0.7))
    _ = counter.consume(invalidSample(at: 1.0))
    _ = counter.consume(pitchSample(at: 1.1, pitch: 0))
    _ = counter.consume(pitchSample(at: 1.4, pitch: 0))

    XCTAssertEqual(counter.completedRepetitions, 0)
    XCTAssertEqual(counter.state, .seekingTarget)
  }

  func testGentleNodFaceLossLongerThanGracePeriodResetsCurrentAttempt() {
    var counter = makeAdaptiveNodCounter(allowsTrackingLoss: true)

    _ = counter.consume(pitchSample(at: 0, pitch: 0))
    _ = counter.consume(pitchSample(at: 0.3, pitch: 0))
    _ = counter.consume(pitchSample(at: 0.4, pitch: 5))
    _ = counter.consume(invalidSample(at: 0.8))
    _ = counter.consume(invalidSample(at: 1.3))
    XCTAssertEqual(
      counter.consume(invalidSample(at: 1.61)),
      .resetAfterTrackingLoss
    )
    XCTAssertEqual(counter.state, .awaitingNeutral)
    XCTAssertEqual(counter.completedRepetitions, 0)
  }

  func testLongGapWithoutExplicitInvalidSampleCannotBridgeGentleNod() {
    var counter = makeAdaptiveNodCounter(allowsTrackingLoss: true)

    _ = counter.consume(pitchSample(at: 0, pitch: 0))
    _ = counter.consume(pitchSample(at: 0.3, pitch: 0))
    _ = counter.consume(pitchSample(at: 0.4, pitch: 5))
    XCTAssertEqual(
      counter.consume(pitchSample(at: 1.0, pitch: 0)),
      .resetAfterTrackingLoss
    )
    XCTAssertEqual(counter.state, .awaitingNeutral)
    XCTAssertEqual(counter.completedRepetitions, 0)
  }

  private func makeCounter() -> RepCounter {
    RepCounter(
      definition: definition,
      calibration: calibration,
      configuration: deterministicConfiguration
    )
  }

  private func makeAdaptiveNodCounter(allowsTrackingLoss: Bool) -> RepCounter {
    let nod = ExercisePlan.v1.exercises.first { $0.kind == .gentleNod }!
    let pitchDefaults = CalibrationProfile.v1Defaults().calibration(for: .pitch)!
    let adaptivePitch = AxisCalibration(
      axis: .pitch,
      neutralDegrees: 0,
      noiseMADDegrees: 1,
      neutralBandDegrees: 4,
      directions: pitchDefaults.directions.map {
        DirectionCalibration(
          axis: $0.axis,
          direction: $0.direction,
          sign: $0.sign,
          comfortablePeakDegrees: 6,
          targetDegrees: 5
        )
      }
    )
    return RepCounter(
      definition: nod,
      calibration: CalibrationProfile(axes: [adaptivePitch]),
      configuration: RepCounterConfiguration(
        minimumTrackingQuality: 0.4,
        maximumInvalidDuration: 0.5,
        maximumSampleGap: 0.5,
        targetReleaseRatio: 0.75,
        filterWindowSize: 1,
        filterAlpha: 1,
        maximumTargetHoldTrackingLossDuration: 1.2,
        allowsTargetHoldDuringTrackingLoss: allowsTrackingLoss
      )
    )
  }

  private func arm(_ counter: inout RepCounter) {
    _ = counter.consume(sample(at: 0, yaw: 0))
    _ = counter.consume(sample(at: 0.3, yaw: 0))
    XCTAssertEqual(counter.state, .seekingTarget)
  }

  private func sample(at timestamp: TimeInterval, yaw: Double) -> MotionSample {
    MotionSample(
      timestamp: timestamp,
      yawDegrees: yaw,
      pitchDegrees: 0,
      rollDegrees: 0,
      trackingQuality: 0.9,
      isFaceValid: true,
      faceCount: 1
    )
  }

  private func invalidSample(at timestamp: TimeInterval) -> MotionSample {
    MotionSample(
      timestamp: timestamp,
      yawDegrees: nil,
      pitchDegrees: nil,
      rollDegrees: nil,
      trackingQuality: 0,
      isFaceValid: false,
      faceCount: 0
    )
  }

  private func pitchSample(at timestamp: TimeInterval, pitch: Double) -> MotionSample {
    MotionSample(
      timestamp: timestamp,
      yawDegrees: 0,
      pitchDegrees: pitch,
      rollDegrees: 0,
      trackingQuality: 0.9,
      isFaceValid: true,
      faceCount: 1
    )
  }
}
