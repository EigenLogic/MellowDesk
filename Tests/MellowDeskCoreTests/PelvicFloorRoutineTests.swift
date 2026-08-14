import XCTest

@testable import MellowDeskCore

final class PelvicFloorRoutineTests: XCTestCase {
  private let routine = PelvicFloorRoutine.v1

  func testV1RoutineIsFourHalfMinuteSegments() {
    XCTAssertEqual(routine.routineVersion, "pelvic-floor-v1.0")
    XCTAssertEqual(
      routine.segments.map(\.id),
      ["slow", "fast", "rock", "quickLiftSlowRelease"]
    )
    XCTAssertEqual(routine.totalDuration, 120, accuracy: 0.0001)
    XCTAssertTrue(routine.safetyNotice.contains("立即停止"))

    for segment in routine.segments {
      XCTAssertEqual(segment.duration, 30, accuracy: 0.0001)
      XCTAssertEqual(
        Double(segment.cycleCount) * segment.cycleDuration,
        segment.duration,
        accuracy: 0.0001,
        "\(segment.id) should hold a whole number of cycles"
      )
    }
  }

  func testEachSegmentUsesItsOwnTempo() {
    let slow = routine.segments[0]
    XCTAssertEqual(slow.cycle.map(\.phase), [.lift, .hold, .release, .rest])
    XCTAssertEqual(slow.cycleDuration, 10, accuracy: 0.0001)
    XCTAssertEqual(slow.liftCount, 3)

    let fast = routine.segments[1]
    XCTAssertEqual(fast.cycle.map(\.phase), [.lift, .release])
    XCTAssertEqual(fast.cycleDuration, 2, accuracy: 0.0001)
    XCTAssertEqual(fast.liftCount, 15)

    let rock = routine.segments[2]
    XCTAssertEqual(rock.cycleDuration, 6, accuracy: 0.0001)
    XCTAssertEqual(rock.liftsPerCycle, 3)
    // Short, short, long: the We Will Rock You pattern, then a full rest beat.
    XCTAssertEqual(rock.cycle.filter { $0.phase == .lift }.map(\.duration), [0.5, 0.5, 1])
    XCTAssertEqual(rock.cycle.last?.phase, .rest)

    let quick = routine.segments[3]
    XCTAssertEqual(quick.cycle.map(\.phase), [.lift, .hold, .release, .rest])
    XCTAssertLessThan(quick.cycle[0].duration, quick.cycle[2].duration)
    XCTAssertEqual(quick.liftCount, 5)
  }

  func testStateWalksSegmentsInOrder() {
    XCTAssertEqual(routine.state(at: 0).segmentIndex, 0)
    XCTAssertEqual(routine.state(at: 29.9).segmentIndex, 0)
    XCTAssertEqual(routine.state(at: 30).segmentIndex, 1)
    XCTAssertEqual(routine.state(at: 59.9).segmentIndex, 1)
    XCTAssertEqual(routine.state(at: 60).segmentIndex, 2)
    XCTAssertEqual(routine.state(at: 90).segmentIndex, 3)
    XCTAssertEqual(routine.state(at: 119.9).segmentIndex, 3)
  }

  func testRingProgressRisesHoldsThenUnwinds() {
    let lift = routine.state(at: 1.5)
    XCTAssertEqual(lift.phase, .lift)
    XCTAssertEqual(lift.ringProgress, 0.5, accuracy: 0.0001)

    let hold = routine.state(at: 4)
    XCTAssertEqual(hold.phase, .hold)
    XCTAssertEqual(hold.ringProgress, 1, accuracy: 0.0001)

    let release = routine.state(at: 6.5)
    XCTAssertEqual(release.phase, .release)
    XCTAssertEqual(release.ringProgress, 0.5, accuracy: 0.0001)

    let rest = routine.state(at: 9)
    XCTAssertEqual(rest.phase, .rest)
    XCTAssertEqual(rest.ringProgress, 0, accuracy: 0.0001)
  }

  func testFastSegmentAlternatesEverySecond() {
    XCTAssertEqual(routine.state(at: 30.5).phase, .lift)
    XCTAssertEqual(routine.state(at: 31.5).phase, .release)
    XCTAssertEqual(routine.state(at: 32.5).phase, .lift)
    XCTAssertEqual(routine.state(at: 32.5).cycleIndex, 1)
  }

  func testRockSegmentPlaysShortShortLongThenRest() {
    XCTAssertEqual(routine.state(at: 60.2).phase, .lift)
    XCTAssertEqual(routine.state(at: 60.7).phase, .release)
    XCTAssertEqual(routine.state(at: 61.2).phase, .lift)
    XCTAssertEqual(routine.state(at: 61.7).phase, .release)
    XCTAssertEqual(routine.state(at: 62.5).phase, .lift)
    XCTAssertEqual(routine.state(at: 63.5).phase, .hold)
    XCTAssertEqual(routine.state(at: 64.5).phase, .release)
    XCTAssertEqual(routine.state(at: 65.5).phase, .rest)
    XCTAssertEqual(routine.state(at: 66.2).cycleIndex, 1)
    XCTAssertEqual(routine.state(at: 66.2).phase, .lift)
  }

  func testQuickLiftSlowReleaseFillsFastAndEmptiesSlowly() {
    let lifted = routine.state(at: 90.5)
    XCTAssertEqual(lifted.phase, .hold)
    XCTAssertEqual(lifted.ringProgress, 1, accuracy: 0.0001)

    let midRelease = routine.state(at: 93.5)
    XCTAssertEqual(midRelease.phase, .release)
    XCTAssertEqual(midRelease.ringProgress, 0.5, accuracy: 0.0001)
  }

  func testCompletedLiftsAccumulateAcrossSegments() {
    XCTAssertEqual(routine.state(at: 0).completedLifts, 0)
    XCTAssertEqual(routine.state(at: 3.5).completedLifts, 1)
    XCTAssertEqual(routine.state(at: 30).completedLifts, 3)
    XCTAssertEqual(routine.state(at: 60).completedLifts, 18)
    XCTAssertEqual(routine.totalLiftCount, 38)
    XCTAssertEqual(routine.state(at: 120).completedLifts, routine.totalLiftCount)
  }

  func testStateClampsOutsideTheRoutine() {
    let finished = routine.state(at: 500)
    XCTAssertTrue(finished.isFinished)
    XCTAssertEqual(finished.segmentIndex, 3)
    XCTAssertEqual(finished.ringProgress, 0, accuracy: 0.0001)
    XCTAssertEqual(finished.totalRemaining, 0, accuracy: 0.0001)
    XCTAssertEqual(finished.segmentProgress, 1, accuracy: 0.0001)

    let start = routine.state(at: -10)
    XCTAssertFalse(start.isFinished)
    XCTAssertEqual(start.segmentIndex, 0)
    XCTAssertEqual(start.elapsed, 0, accuracy: 0.0001)
    XCTAssertEqual(start.totalRemaining, 120, accuracy: 0.0001)
  }

  func testSegmentAndBeatIdentityAdvanceWithTime() {
    XCTAssertEqual(routine.state(at: 0).beatID, "0-0-0")
    XCTAssertEqual(routine.state(at: 4).beatID, "0-0-1")
    XCTAssertEqual(routine.state(at: 14).beatID, "0-1-1")
    XCTAssertEqual(routine.state(at: 0).segmentProgress, 0, accuracy: 0.0001)
    XCTAssertEqual(routine.state(at: 15).segmentProgress, 0.5, accuracy: 0.0001)
  }
}
