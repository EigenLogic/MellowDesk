import Foundation

public enum MellowDeskCoreModule {
  public static let version = "0.1.0"
  public static let routineVersion = ExercisePlan.v1.routineVersion
}

public enum ExerciseKind: String, CaseIterable, Codable, Hashable, Sendable {
  case neckRotation
  case lateralFlexion
  case gentleNod
}

public enum MotionAxis: String, CaseIterable, Codable, Hashable, Sendable {
  case yaw
  case pitch
  case roll
}

public enum MotionDirection: String, CaseIterable, Codable, Hashable, Sendable {
  case left
  case right
  case down

  public var localizedName: String {
    switch self {
    case .left: return "左侧"
    case .right: return "右侧"
    case .down: return "向下"
    }
  }
}

public struct ExerciseDefinition: Identifiable, Codable, Equatable, Sendable {
  public let kind: ExerciseKind
  public let displayName: String
  public let instruction: String
  public let safetyBoundary: String
  public let axis: MotionAxis
  public let directions: [MotionDirection]
  public let repetitionsPerDirection: Int
  public let defaultTargetDegrees: Double
  public let neutralBandDegrees: Double
  public let targetHoldDuration: TimeInterval
  public let neutralHoldDuration: TimeInterval

  public var id: ExerciseKind { kind }
  public var targetRepetitions: Int { repetitionsPerDirection * directions.count }
  public var isBilateral: Bool { directions.count == 2 }

  /// Uses the stable movement observed during direction calibration to make
  /// Vision's lower-amplitude pitch signal practical without changing the
  /// exercise instruction or the full target-hold-return counting sequence.
  public func recognitionTargetDegrees(observedPeakDegrees: Double) -> Double {
    guard kind == .gentleNod,
      observedPeakDegrees.isFinite,
      observedPeakDegrees > 0
    else { return defaultTargetDegrees }

    let upperBound = min(defaultTargetDegrees, 8)
    let lowerBound = min(5, upperBound)
    return min(max(observedPeakDegrees * 0.6, lowerBound), upperBound)
  }

  public init(
    kind: ExerciseKind,
    displayName: String,
    instruction: String,
    safetyBoundary: String,
    axis: MotionAxis,
    directions: [MotionDirection],
    repetitionsPerDirection: Int,
    defaultTargetDegrees: Double,
    neutralBandDegrees: Double,
    targetHoldDuration: TimeInterval = 0.3,
    neutralHoldDuration: TimeInterval = 0.3
  ) {
    self.kind = kind
    self.displayName = displayName
    self.instruction = instruction
    self.safetyBoundary = safetyBoundary
    self.axis = axis
    self.directions = directions
    self.repetitionsPerDirection = max(0, repetitionsPerDirection)
    self.defaultTargetDegrees = max(0, defaultTargetDegrees)
    self.neutralBandDegrees = max(0, neutralBandDegrees)
    self.targetHoldDuration = max(0.3, targetHoldDuration)
    self.neutralHoldDuration = max(0.3, neutralHoldDuration)
  }
}

public struct ExercisePlan: Codable, Equatable, Sendable {
  public let routineVersion: String
  public let displayName: String
  public let safetyNotice: String
  public let exercises: [ExerciseDefinition]

  public init(
    routineVersion: String,
    displayName: String,
    safetyNotice: String,
    exercises: [ExerciseDefinition]
  ) {
    self.routineVersion = routineVersion
    self.displayName = displayName
    self.safetyNotice = safetyNotice
    self.exercises = exercises
  }

  public static let v1 = ExercisePlan(
    routineVersion: "neck-ease-v1.0",
    displayName: "办公颈肩舒展",
    safetyNotice: "全程缓慢、无痛，只在舒适活动范围内练习。若出现疼痛、眩晕、麻木、视物异常或恶心，请立即停止；本训练不能替代医疗诊断或治疗。",
    exercises: [
      ExerciseDefinition(
        kind: .neckRotation,
        displayName: "左右缓慢转头",
        instruction: "坐直并放松双肩，缓慢将头转向提示侧，短暂停留后回到正中；左右交替进行。",
        safetyBoundary: "只转到舒适范围，不后仰、不耸肩、不追求最大角度。每侧 4 次；任何不适都应立即停止。",
        axis: .yaw,
        directions: [.left, .right],
        repetitionsPerDirection: 4,
        defaultTargetDegrees: 15,
        neutralBandDegrees: 6
      ),
      ExerciseDefinition(
        kind: .lateralFlexion,
        displayName: "左右轻柔侧屈",
        instruction: "面向前方，耳朵缓慢向提示侧肩膀靠近，肩膀保持放松，短暂停留后回到正中。",
        safetyBoundary: "不要抬肩、转头或用力压头，也无需让耳朵碰到肩膀。每侧 3 次；任何不适都应立即停止。",
        axis: .roll,
        directions: [.left, .right],
        repetitionsPerDirection: 3,
        defaultTargetDegrees: 9,
        neutralBandDegrees: 5
      ),
      ExerciseDefinition(
        kind: .gentleNod,
        displayName: "轻柔低头并回正",
        instruction: "保持肩膀放松，像轻轻点头一样让下巴缓慢向下移动一小段，短暂停留后回到自然中立位。",
        safetyBoundary: "本动作不包含向后仰头；不要快速点头或强迫下巴贴胸。完成 5 次；任何不适都应立即停止。",
        axis: .pitch,
        directions: [.down],
        repetitionsPerDirection: 5,
        defaultTargetDegrees: 10,
        neutralBandDegrees: 5
      ),
    ]
  )
}
