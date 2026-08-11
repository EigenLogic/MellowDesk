import AVFoundation
import CoreMedia
import ImageIO
import MellowDeskCore
import Vision

/// Converts camera frames into raw Vision head-pose samples.
///
/// Call this type from one serial queue. It deliberately does not calibrate,
/// smooth, or classify poses; those operations belong to `MellowDeskCore`.
public final class VisionHeadPoseEstimator {
  public struct Configuration: Equatable {
    public var maximumFramesPerSecond: Double
    public var minimumFaceConfidence: Double
    public var minimumFaceDimension: Double
    public var ambiguousFaceAreaRatio: Double
    public var imageOrientation: CGImagePropertyOrientation

    public init(
      maximumFramesPerSecond: Double = 12,
      minimumFaceConfidence: Double = 0.25,
      minimumFaceDimension: Double = 0.08,
      ambiguousFaceAreaRatio: Double = 0.6,
      imageOrientation: CGImagePropertyOrientation = .up
    ) {
      self.maximumFramesPerSecond = max(1, maximumFramesPerSecond)
      self.minimumFaceConfidence = min(max(0, minimumFaceConfidence), 1)
      self.minimumFaceDimension = min(max(0, minimumFaceDimension), 1)
      self.ambiguousFaceAreaRatio = min(max(0, ambiguousFaceAreaRatio), 1)
      self.imageOrientation = imageOrientation
    }
  }

  public enum EstimationError: LocalizedError {
    case visionRequestFailed(String)

    public var errorDescription: String? {
      switch self {
      case .visionRequestFailed(let message):
        return "Vision head-pose estimation failed: \(message)"
      }
    }
  }

  private let configuration: Configuration
  private let request: VNDetectFaceRectanglesRequest
  private var lastAnalysisTime: TimeInterval?

  public init(configuration: Configuration = Configuration()) {
    self.configuration = configuration

    let request = VNDetectFaceRectanglesRequest()
    // Revision 3 is stable on the macOS 13 deployment target and is the
    // first revision to report continuous yaw, pitch, and roll together.
    request.revision = VNDetectFaceRectanglesRequestRevision3
    self.request = request
  }

  /// Analyzes a frame at no more than the configured frequency.
  ///
  /// - Returns: `nil` only when the frame is intentionally throttled. Every
  ///   analyzed frame returns a sample, including explicit invalid samples
  ///   for zero faces, multiple faces, or incomplete pose angles.
  public func process(_ sampleBuffer: CMSampleBuffer) throws -> MotionSample? {
    let timestamp = ProcessInfo.processInfo.systemUptime
    guard shouldAnalyze(at: timestamp) else {
      return nil
    }

    let handler = VNImageRequestHandler(
      cmSampleBuffer: sampleBuffer,
      orientation: configuration.imageOrientation,
      options: [:]
    )

    do {
      try handler.perform([request])
    } catch {
      throw EstimationError.visionRequestFailed(error.localizedDescription)
    }

    let faces = request.results ?? []
    let candidates = faces.enumerated().map { index, face in
      FaceCandidate(
        sourceIndex: index,
        confidence: Double(face.confidence),
        width: face.boundingBox.width,
        height: face.boundingBox.height
      )
    }
    let selection = PrimaryFaceSelector(
      minimumConfidence: configuration.minimumFaceConfidence,
      minimumDimension: configuration.minimumFaceDimension,
      ambiguousFaceAreaRatio: configuration.ambiguousFaceAreaRatio
    ).select(from: candidates)

    let face: VNFaceObservation
    switch selection {
    case .none:
      return invalidSample(
        timestamp: timestamp,
        faceCount: 0,
        quality: faces.map { Double($0.confidence) }.max() ?? 0
      )
    case .ambiguous(let faceCount):
      return invalidSample(
        timestamp: timestamp,
        faceCount: faceCount,
        quality: faces.map { Double($0.confidence) }.max() ?? 0
      )
    case .primary(let sourceIndex):
      face = faces[sourceIndex]
    }

    let yaw = degrees(from: face.yaw)
    let pitch = degrees(from: face.pitch)
    let roll = degrees(from: face.roll)
    let confidence = clampedQuality(Double(face.confidence))
    let hasCompletePose = yaw != nil && pitch != nil && roll != nil

    return MotionSample(
      timestamp: timestamp,
      yawDegrees: yaw,
      pitchDegrees: pitch,
      rollDegrees: roll,
      trackingQuality: confidence,
      isFaceValid: hasCompletePose,
      faceCount: 1
    )
  }

  /// Clears the throttle clock between exercise sessions.
  public func reset() {
    lastAnalysisTime = nil
  }

  private func shouldAnalyze(at timestamp: TimeInterval) -> Bool {
    guard let lastAnalysisTime else {
      self.lastAnalysisTime = timestamp
      return true
    }

    let elapsed = timestamp - lastAnalysisTime
    let minimumInterval = 1 / max(1, configuration.maximumFramesPerSecond)
    if elapsed < 0 || elapsed >= minimumInterval {
      self.lastAnalysisTime = timestamp
      return true
    }
    return false
  }

  private func degrees(from angle: NSNumber?) -> Double? {
    guard let radians = angle?.doubleValue, radians.isFinite else {
      return nil
    }

    let degrees = radians * 180 / Double.pi
    return degrees.isFinite ? degrees : nil
  }

  private func invalidSample(
    timestamp: TimeInterval,
    faceCount: Int,
    quality: Double
  ) -> MotionSample {
    MotionSample(
      timestamp: timestamp,
      yawDegrees: nil,
      pitchDegrees: nil,
      rollDegrees: nil,
      trackingQuality: clampedQuality(quality),
      isFaceValid: false,
      faceCount: faceCount
    )
  }

  private func clampedQuality(_ quality: Double) -> Double {
    min(max(quality.isFinite ? quality : 0, 0), 1)
  }
}
