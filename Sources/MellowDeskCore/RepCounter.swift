import Foundation

public enum RepCounterState: String, Codable, Equatable, Sendable {
  case awaitingNeutral
  case seekingTarget
  case holdingTarget
  case returningToNeutral
  case finished
}

public enum RepCounterEvent: Equatable, Sendable {
  case none
  case stateChanged(RepCounterState)
  case repCompleted(direction: MotionDirection, completedRepetitions: Int)
  case finished
  case trackingLost
  case resetAfterTrackingLoss
}

public struct RepCounterConfiguration: Equatable, Sendable {
  public let minimumTrackingQuality: Double
  public let maximumInvalidDuration: TimeInterval
  public let maximumSampleGap: TimeInterval
  public let targetReleaseRatio: Double
  public let filterWindowSize: Int
  public let filterAlpha: Double
  public let maximumTargetHoldTrackingLossDuration: TimeInterval
  public let allowsTargetHoldDuringTrackingLoss: Bool

  public init(
    minimumTrackingQuality: Double = 0.4,
    maximumInvalidDuration: TimeInterval = 0.5,
    maximumSampleGap: TimeInterval = 0.5,
    targetReleaseRatio: Double = 0.75,
    filterWindowSize: Int = 3,
    filterAlpha: Double = 0.35,
    maximumTargetHoldTrackingLossDuration: TimeInterval = 1.2,
    allowsTargetHoldDuringTrackingLoss: Bool = false
  ) {
    self.minimumTrackingQuality = min(max(minimumTrackingQuality, 0), 1)
    self.maximumInvalidDuration = max(0, maximumInvalidDuration)
    self.maximumSampleGap = max(0, maximumSampleGap)
    self.targetReleaseRatio = min(max(targetReleaseRatio, 0), 1)
    self.filterWindowSize = max(1, filterWindowSize)
    self.filterAlpha = min(max(filterAlpha, 0.01), 1)
    self.maximumTargetHoldTrackingLossDuration = max(
      0,
      maximumTargetHoldTrackingLossDuration
    )
    self.allowsTargetHoldDuringTrackingLoss = allowsTargetHoldDuringTrackingLoss
  }
}

public struct RepCounter: Sendable {
  public let definition: ExerciseDefinition
  public let calibration: CalibrationProfile
  public let configuration: RepCounterConfiguration

  public private(set) var state: RepCounterState = .awaitingNeutral
  public private(set) var completedRepetitions: Int = 0
  public private(set) var completedRepetitionsByDirection: [MotionDirection: Int] = [:]

  public var expectedDirection: MotionDirection? {
    guard state != .finished, directionIndex < directionSequence.count else { return nil }
    return directionSequence[directionIndex]
  }

  public var targetRepetitions: Int { directionSequence.count }
  public var isFinished: Bool { state == .finished }

  private let directionSequence: [MotionDirection]
  private var directionIndex: Int = 0
  private var neutralEvidence: TimeInterval = 0
  private var targetEvidence: TimeInterval = 0
  private var invalidDuration: TimeInterval = 0
  private var neutralObservationIsContinuous = false
  private var lastTimestamp: TimeInterval?
  private var filter: MedianEMAFilter

  public init(
    definition: ExerciseDefinition,
    calibration: CalibrationProfile,
    configuration: RepCounterConfiguration = RepCounterConfiguration()
  ) {
    self.definition = definition
    self.calibration = calibration
    self.configuration = configuration
    self.directionSequence = Self.makeAlternatingSequence(for: definition)
    self.filter = MedianEMAFilter(
      windowSize: configuration.filterWindowSize,
      alpha: configuration.filterAlpha
    )
    if directionSequence.isEmpty {
      self.state = .finished
    }
  }

  public mutating func consume(_ sample: MotionSample) -> RepCounterEvent {
    guard state != .finished else { return .none }
    guard sample.timestamp.isFinite else { return .none }

    let deltaTime: TimeInterval
    if let lastTimestamp {
      guard sample.timestamp > lastTimestamp else { return .none }
      deltaTime = sample.timestamp - lastTimestamp
    } else {
      deltaTime = 0
    }
    lastTimestamp = sample.timestamp

    if deltaTime > configuration.maximumSampleGap {
      resetCurrentRep(resetFilter: true)
      return .resetAfterTrackingLoss
    }

    guard
      sample.isUsable(
        for: definition.axis,
        minimumTrackingQuality: configuration.minimumTrackingQuality
      ), let rawValue = sample.value(for: definition.axis)
    else {
      invalidDuration += deltaTime
      neutralEvidence = 0
      neutralObservationIsContinuous = false
      let canBridgeTargetHold =
        definition.kind == .gentleNod
        && configuration.allowsTargetHoldDuringTrackingLoss
        && sample.faceCount <= 1
        && state == .holdingTarget
      let allowedInvalidDuration =
        canBridgeTargetHold
        ? configuration.maximumTargetHoldTrackingLossDuration
        : configuration.maximumInvalidDuration
      if invalidDuration > allowedInvalidDuration {
        resetCurrentRep(resetFilter: true)
        return .resetAfterTrackingLoss
      }
      if canBridgeTargetHold {
        targetEvidence += deltaTime
        filter.reset()
      } else if state == .holdingTarget {
        targetEvidence = 0
      }
      return .trackingLost
    }

    let resumedAfterInvalidFrame = invalidDuration > 0
    let completedTargetHoldDuringTrackingLoss =
      resumedAfterInvalidFrame
      && configuration.allowsTargetHoldDuringTrackingLoss
      && definition.kind == .gentleNod
      && state == .holdingTarget
      && hasEnoughEvidence(targetEvidence, required: definition.targetHoldDuration)
    invalidDuration = 0
    let evidenceDelta = resumedAfterInvalidFrame ? 0 : deltaTime

    guard let expectedDirection,
      let axisCalibration = calibration.calibration(for: definition.axis),
      let directionCalibration = axisCalibration.target(for: expectedDirection)
    else {
      return .none
    }

    let filteredValue = filter.add(rawValue)
    let calibratedDelta = filteredValue - axisCalibration.neutralDegrees
    let projectedValue = directionCalibration.sign * calibratedDelta
    let target =
      directionCalibration.targetDegrees > 0
      ? directionCalibration.targetDegrees
      : definition.defaultTargetDegrees
    let neutralBand = min(
      max(definition.neutralBandDegrees, axisCalibration.neutralBandDegrees),
      target * 0.5
    )
    let isNeutral = abs(calibratedDelta) <= neutralBand

    if completedTargetHoldDuringTrackingLoss {
      targetEvidence = 0
      neutralEvidence = 0
      neutralObservationIsContinuous = false
      state = .returningToNeutral
      return .stateChanged(state)
    }

    switch state {
    case .awaitingNeutral:
      if accumulateNeutralEvidence(isNeutral: isNeutral, deltaTime: evidenceDelta) {
        neutralEvidence = 0
        neutralObservationIsContinuous = false
        state = .seekingTarget
        return .stateChanged(state)
      }

    case .seekingTarget:
      neutralObservationIsContinuous = false
      if projectedValue >= target {
        targetEvidence = 0
        state = .holdingTarget
        return .stateChanged(state)
      }

    case .holdingTarget:
      neutralObservationIsContinuous = false
      if projectedValue >= target * configuration.targetReleaseRatio {
        targetEvidence += evidenceDelta
        if hasEnoughEvidence(targetEvidence, required: definition.targetHoldDuration) {
          targetEvidence = 0
          neutralEvidence = 0
          neutralObservationIsContinuous = false
          state = .returningToNeutral
          return .stateChanged(state)
        }
      } else {
        targetEvidence = 0
        state = .seekingTarget
        return .stateChanged(state)
      }

    case .returningToNeutral:
      if accumulateNeutralEvidence(isNeutral: isNeutral, deltaTime: evidenceDelta) {
        return completeCurrentRepetition(direction: expectedDirection)
      }

    case .finished:
      return .none
    }

    return .none
  }

  /// Cancels only the in-flight repetition after a pause or processing gap.
  /// Completed repetitions and the expected direction are preserved.
  public mutating func invalidateCurrentAttempt() {
    guard state != .finished else { return }
    resetCurrentRep(resetFilter: true)
  }

  private mutating func completeCurrentRepetition(direction: MotionDirection) -> RepCounterEvent {
    completedRepetitions += 1
    completedRepetitionsByDirection[direction, default: 0] += 1
    directionIndex += 1
    neutralEvidence = 0
    targetEvidence = 0
    neutralObservationIsContinuous = false

    if directionIndex >= directionSequence.count {
      state = .finished
      return .finished
    }

    // A fully visible neutral hold just completed, so the next alternating side is armed.
    state = .seekingTarget
    return .repCompleted(direction: direction, completedRepetitions: completedRepetitions)
  }

  private mutating func resetCurrentRep(resetFilter: Bool) {
    state = .awaitingNeutral
    neutralEvidence = 0
    targetEvidence = 0
    invalidDuration = 0
    neutralObservationIsContinuous = false
    lastTimestamp = nil
    if resetFilter {
      filter.reset()
    }
  }

  private func hasEnoughEvidence(_ value: TimeInterval, required: TimeInterval) -> Bool {
    value + 1e-9 >= required
  }

  private mutating func accumulateNeutralEvidence(
    isNeutral: Bool,
    deltaTime: TimeInterval
  ) -> Bool {
    guard isNeutral else {
      neutralEvidence = 0
      neutralObservationIsContinuous = false
      return false
    }

    if neutralObservationIsContinuous {
      neutralEvidence += deltaTime
    } else {
      neutralObservationIsContinuous = true
    }
    return hasEnoughEvidence(neutralEvidence, required: definition.neutralHoldDuration)
  }

  private static func makeAlternatingSequence(for definition: ExerciseDefinition)
    -> [MotionDirection]
  {
    guard definition.repetitionsPerDirection > 0, !definition.directions.isEmpty else {
      return []
    }

    var sequence: [MotionDirection] = []
    for _ in 0..<definition.repetitionsPerDirection {
      sequence.append(contentsOf: definition.directions)
    }
    return sequence
  }
}
