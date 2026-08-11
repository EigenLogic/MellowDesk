import Foundation

public struct MotionSample: Codable, Equatable, Sendable {
  public let timestamp: TimeInterval
  public let yawDegrees: Double?
  public let pitchDegrees: Double?
  public let rollDegrees: Double?
  public let trackingQuality: Double
  public let isFaceValid: Bool
  public let faceCount: Int

  public init(
    timestamp: TimeInterval,
    yawDegrees: Double?,
    pitchDegrees: Double?,
    rollDegrees: Double?,
    trackingQuality: Double,
    isFaceValid: Bool,
    faceCount: Int
  ) {
    self.timestamp = timestamp
    self.yawDegrees = yawDegrees
    self.pitchDegrees = pitchDegrees
    self.rollDegrees = rollDegrees
    self.trackingQuality =
      trackingQuality.isFinite
      ? min(max(trackingQuality, 0), 1)
      : 0
    self.isFaceValid = isFaceValid
    self.faceCount = max(0, faceCount)
  }

  public func value(for axis: MotionAxis) -> Double? {
    switch axis {
    case .yaw: return yawDegrees
    case .pitch: return pitchDegrees
    case .roll: return rollDegrees
    }
  }

  public func isUsable(for axis: MotionAxis, minimumTrackingQuality: Double) -> Bool {
    guard let axisValue = value(for: axis) else { return false }
    return isFaceValid
      && faceCount == 1
      && trackingQuality >= minimumTrackingQuality
      && axisValue.isFinite
  }
}
