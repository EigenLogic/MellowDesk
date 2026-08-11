import XCTest

@testable import MellowDeskCore

final class CalibrationTests: XCTestCase {
  func testMedianFilterRejectsSingleSpikeAndEMAIsDeterministic() {
    var medianFilter = MedianEMAFilter(windowSize: 3, alpha: 1)
    XCTAssertEqual(medianFilter.add(1), 1, accuracy: 0.0001)
    XCTAssertEqual(medianFilter.add(100), 50.5, accuracy: 0.0001)
    XCTAssertEqual(medianFilter.add(2), 2, accuracy: 0.0001)

    var emaFilter = MedianEMAFilter(windowSize: 1, alpha: 0.5)
    XCTAssertEqual(emaFilter.add(0), 0, accuracy: 0.0001)
    XCTAssertEqual(emaFilter.add(10), 5, accuracy: 0.0001)
  }

  func testNeutralCalibrationUsesMedianAndMAD() throws {
    let yawValues: [Double] = [9, 10, 10, 10, 11]
    let samples = yawValues.enumerated().map { index, yaw in
      MotionSample(
        timestamp: Double(index) * 0.1,
        yawDegrees: yaw,
        pitchDegrees: -2,
        rollDegrees: 3,
        trackingQuality: 0.9,
        isFaceValid: true,
        faceCount: 1
      )
    }
    let calibrator = NeutralCalibrator(
      minimumValidSamples: 5,
      minimumTrackingQuality: 0.4,
      minimumNeutralBandDegrees: 4,
      noiseMultiplier: 3
    )

    let profile = try calibrator.calibrate(samples: samples)

    XCTAssertEqual(profile.calibration(for: .yaw)?.neutralDegrees ?? .nan, 10, accuracy: 0.0001)
    XCTAssertEqual(profile.calibration(for: .yaw)?.noiseMADDegrees ?? .nan, 0, accuracy: 0.0001)
    XCTAssertEqual(profile.calibration(for: .yaw)?.neutralBandDegrees ?? .nan, 4, accuracy: 0.0001)
    XCTAssertEqual(profile.calibration(for: .pitch)?.neutralDegrees ?? .nan, -2, accuracy: 0.0001)
    XCTAssertEqual(profile.calibration(for: .roll)?.neutralDegrees ?? .nan, 3, accuracy: 0.0001)
  }

  func testNeutralCalibrationRejectsTooFewValidSamples() {
    let samples = [
      MotionSample(
        timestamp: 0,
        yawDegrees: 0,
        pitchDegrees: 0,
        rollDegrees: 0,
        trackingQuality: 0.2,
        isFaceValid: true,
        faceCount: 1
      )
    ]

    XCTAssertThrowsError(try NeutralCalibrator(minimumValidSamples: 2).calibrate(samples: samples))
    { error in
      XCTAssertEqual(
        error as? NeutralCalibrationError,
        .insufficientValidSamples(axis: .yaw, required: 2, actual: 0)
      )
    }
  }

  func testNeutralCalibrationRejectsUnstableHeadMovement() {
    let yawValues: [Double] = [-6, -4, -2, 0, 2, 4, 6]
    let samples = yawValues.enumerated().map { index, yaw in
      MotionSample(
        timestamp: Double(index) * 0.1,
        yawDegrees: yaw,
        pitchDegrees: 0,
        rollDegrees: 0,
        trackingQuality: 0.9,
        isFaceValid: true,
        faceCount: 1
      )
    }

    XCTAssertThrowsError(
      try NeutralCalibrator(minimumValidSamples: yawValues.count).calibrate(samples: samples)
    ) { error in
      guard let calibrationError = error as? NeutralCalibrationError,
        case .unstableSamples(axis: .yaw, noiseMADDegrees: let mad) = calibrationError
      else {
        return XCTFail("Expected unstable yaw calibration, got \(error)")
      }
      XCTAssertEqual(mad, 4, accuracy: 0.0001)
    }
  }

  func testBestEffortCalibrationClampsNoisySamplesInsteadOfBlocking() throws {
    let yawValues: [Double] = [-6, -4, -2, 0, 2, 4, 6]
    let samples = yawValues.enumerated().map { index, yaw in
      MotionSample(
        timestamp: Double(index) * 0.1,
        yawDegrees: yaw,
        pitchDegrees: 0,
        rollDegrees: 0,
        trackingQuality: 0.9,
        isFaceValid: true,
        faceCount: 1
      )
    }
    let calibrator = NeutralCalibrator(
      minimumValidSamples: yawValues.count,
      rejectsUnstableSamples: false
    )

    let profile = try calibrator.calibrate(samples: samples)
    let yaw = try XCTUnwrap(profile.calibration(for: .yaw))

    XCTAssertEqual(yaw.neutralDegrees, 0, accuracy: 0.0001)
    XCTAssertEqual(yaw.noiseMADDegrees, 4, accuracy: 0.0001)
    XCTAssertEqual(yaw.neutralBandDegrees, 6.75, accuracy: 0.0001)
  }
}
