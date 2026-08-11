import Foundation

public struct MedianEMAFilter: Sendable {
  public let windowSize: Int
  public let alpha: Double

  private var values: [Double] = []
  private var ema: Double?

  public init(windowSize: Int = 3, alpha: Double = 0.35) {
    let positiveWindow = max(1, windowSize)
    self.windowSize = positiveWindow.isMultiple(of: 2) ? positiveWindow + 1 : positiveWindow
    self.alpha = min(max(alpha, 0.01), 1)
  }

  public mutating func add(_ value: Double) -> Double {
    values.append(value)
    if values.count > windowSize {
      values.removeFirst(values.count - windowSize)
    }

    let median = SignalStatistics.median(values) ?? value
    if let previous = ema {
      ema = alpha * median + (1 - alpha) * previous
    } else {
      ema = median
    }
    return ema ?? median
  }

  public mutating func reset() {
    values.removeAll(keepingCapacity: true)
    ema = nil
  }
}

public struct DirectionCalibration: Codable, Equatable, Sendable {
  public let axis: MotionAxis
  public let direction: MotionDirection
  /// Multiplies the calibrated axis delta so movement toward this direction is positive.
  public let sign: Double
  public let comfortablePeakDegrees: Double
  public let targetDegrees: Double

  public init(
    axis: MotionAxis,
    direction: MotionDirection,
    sign: Double,
    comfortablePeakDegrees: Double,
    targetDegrees: Double
  ) {
    self.axis = axis
    self.direction = direction
    self.sign = sign < 0 ? -1 : 1
    self.comfortablePeakDegrees = max(0, comfortablePeakDegrees)
    self.targetDegrees = max(0, targetDegrees)
  }
}

public struct AxisCalibration: Codable, Equatable, Sendable {
  public let axis: MotionAxis
  public let neutralDegrees: Double
  public let noiseMADDegrees: Double
  public let neutralBandDegrees: Double
  public let directions: [DirectionCalibration]

  public init(
    axis: MotionAxis,
    neutralDegrees: Double,
    noiseMADDegrees: Double,
    neutralBandDegrees: Double,
    directions: [DirectionCalibration]
  ) {
    self.axis = axis
    self.neutralDegrees = neutralDegrees
    self.noiseMADDegrees = max(0, noiseMADDegrees)
    self.neutralBandDegrees = max(0, neutralBandDegrees)
    self.directions = directions.filter { $0.axis == axis }
  }

  public func target(for direction: MotionDirection) -> DirectionCalibration? {
    directions.first { $0.direction == direction }
  }
}

public struct CalibrationProfile: Codable, Equatable, Sendable {
  public let axes: [AxisCalibration]

  public init(axes: [AxisCalibration]) {
    self.axes = axes
  }

  public func calibration(for axis: MotionAxis) -> AxisCalibration? {
    axes.first { $0.axis == axis }
  }

  public func target(for axis: MotionAxis, direction: MotionDirection) -> DirectionCalibration? {
    calibration(for: axis)?.target(for: direction)
  }

  public static func v1Defaults(
    neutralYawDegrees: Double = 0,
    neutralPitchDegrees: Double = 0,
    neutralRollDegrees: Double = 0,
    leftYawSign: Double = -1,
    leftRollSign: Double = -1,
    downPitchSign: Double = 1
  ) -> CalibrationProfile {
    let definitions = ExercisePlan.v1.exercises
    let rotation = definitions.first { $0.kind == .neckRotation }!
    let flexion = definitions.first { $0.kind == .lateralFlexion }!
    let nod = definitions.first { $0.kind == .gentleNod }!

    return CalibrationProfile(axes: [
      AxisCalibration(
        axis: .yaw,
        neutralDegrees: neutralYawDegrees,
        noiseMADDegrees: 0,
        neutralBandDegrees: rotation.neutralBandDegrees,
        directions: [
          DirectionCalibration(
            axis: .yaw,
            direction: .left,
            sign: leftYawSign,
            comfortablePeakDegrees: rotation.defaultTargetDegrees / 0.6,
            targetDegrees: rotation.defaultTargetDegrees
          ),
          DirectionCalibration(
            axis: .yaw,
            direction: .right,
            sign: -leftYawSign,
            comfortablePeakDegrees: rotation.defaultTargetDegrees / 0.6,
            targetDegrees: rotation.defaultTargetDegrees
          ),
        ]
      ),
      AxisCalibration(
        axis: .pitch,
        neutralDegrees: neutralPitchDegrees,
        noiseMADDegrees: 0,
        neutralBandDegrees: nod.neutralBandDegrees,
        directions: [
          DirectionCalibration(
            axis: .pitch,
            direction: .down,
            sign: downPitchSign,
            comfortablePeakDegrees: nod.defaultTargetDegrees / 0.6,
            targetDegrees: nod.defaultTargetDegrees
          )
        ]
      ),
      AxisCalibration(
        axis: .roll,
        neutralDegrees: neutralRollDegrees,
        noiseMADDegrees: 0,
        neutralBandDegrees: flexion.neutralBandDegrees,
        directions: [
          DirectionCalibration(
            axis: .roll,
            direction: .left,
            sign: leftRollSign,
            comfortablePeakDegrees: flexion.defaultTargetDegrees / 0.6,
            targetDegrees: flexion.defaultTargetDegrees
          ),
          DirectionCalibration(
            axis: .roll,
            direction: .right,
            sign: -leftRollSign,
            comfortablePeakDegrees: flexion.defaultTargetDegrees / 0.6,
            targetDegrees: flexion.defaultTargetDegrees
          ),
        ]
      ),
    ])
  }
}

public enum NeutralCalibrationError: Error, Equatable {
  case insufficientValidSamples(axis: MotionAxis, required: Int, actual: Int)
  case unstableSamples(axis: MotionAxis, noiseMADDegrees: Double)
}

public struct NeutralCalibrator: Sendable {
  public let minimumValidSamples: Int
  public let minimumTrackingQuality: Double
  public let minimumNeutralBandDegrees: Double
  public let noiseMultiplier: Double
  public let rejectsUnstableSamples: Bool

  public init(
    minimumValidSamples: Int = 10,
    minimumTrackingQuality: Double = 0.4,
    minimumNeutralBandDegrees: Double = 4,
    noiseMultiplier: Double = 3,
    rejectsUnstableSamples: Bool = true
  ) {
    self.minimumValidSamples = max(1, minimumValidSamples)
    self.minimumTrackingQuality = min(max(minimumTrackingQuality, 0), 1)
    self.minimumNeutralBandDegrees = max(0, minimumNeutralBandDegrees)
    self.noiseMultiplier = max(0, noiseMultiplier)
    self.rejectsUnstableSamples = rejectsUnstableSamples
  }

  public func calibrate(
    samples: [MotionSample],
    axes: [MotionAxis] = MotionAxis.allCases,
    directionCalibrations: [DirectionCalibration] = CalibrationProfile.v1Defaults().axes.flatMap(
      \.directions)
  ) throws -> CalibrationProfile {
    var calibratedAxes: [AxisCalibration] = []

    for axis in axes {
      let values = samples.compactMap { sample -> Double? in
        guard sample.isUsable(for: axis, minimumTrackingQuality: minimumTrackingQuality) else {
          return nil
        }
        return sample.value(for: axis)
      }

      guard values.count >= minimumValidSamples else {
        throw NeutralCalibrationError.insufficientValidSamples(
          axis: axis,
          required: minimumValidSamples,
          actual: values.count
        )
      }

      let neutral = SignalStatistics.median(values) ?? 0
      let deviations = values.map { abs($0 - neutral) }
      let mad = SignalStatistics.median(deviations) ?? 0
      let directionTargets =
        directionCalibrations
        .filter { $0.axis == axis && $0.targetDegrees > 0 }
        .map(\.targetDegrees)
      let smallestTarget = directionTargets.min() ?? minimumNeutralBandDegrees * 2
      let maximumNeutralBand = max(minimumNeutralBandDegrees, smallestTarget * 0.45)
      let measuredNeutralBand = max(minimumNeutralBandDegrees, noiseMultiplier * mad)
      if rejectsUnstableSamples && measuredNeutralBand > maximumNeutralBand {
        throw NeutralCalibrationError.unstableSamples(
          axis: axis,
          noiseMADDegrees: mad
        )
      }
      let neutralBand = min(measuredNeutralBand, maximumNeutralBand)

      calibratedAxes.append(
        AxisCalibration(
          axis: axis,
          neutralDegrees: neutral,
          noiseMADDegrees: mad,
          neutralBandDegrees: neutralBand,
          directions: directionCalibrations.filter { $0.axis == axis }
        ))
    }

    return CalibrationProfile(axes: calibratedAxes)
  }
}

enum SignalStatistics {
  static func median(_ values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    let middle = sorted.count / 2
    if sorted.count.isMultiple(of: 2) {
      return (sorted[middle - 1] + sorted[middle]) / 2
    }
    return sorted[middle]
  }
}
