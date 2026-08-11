import Foundation

public enum WorkoutSessionStatus: String, Codable, Equatable, Hashable, Sendable {
  case inProgress
  case completed
  case skipped
  case cancelled
}

public enum CompletionMode: String, Codable, Equatable, Hashable, Sendable {
  case camera
  case timer
  case manual
}

public struct ExerciseResult: Codable, Equatable, Sendable {
  public let exerciseID: ExerciseKind
  public let targetReps: Int
  public let completedReps: Int
  public let mode: CompletionMode

  public init(
    exerciseID: ExerciseKind,
    targetReps: Int,
    completedReps: Int,
    mode: CompletionMode
  ) {
    self.exerciseID = exerciseID
    self.targetReps = max(0, targetReps)
    self.completedReps = max(0, completedReps)
    self.mode = mode
  }

  public var isComplete: Bool {
    targetReps > 0 && completedReps >= targetReps
  }

  public var completionRate: Double {
    guard targetReps > 0 else { return 0 }
    return min(Double(completedReps) / Double(targetReps), 1)
  }
}

public struct WorkoutSession: Identifiable, Codable, Equatable, Sendable {
  public let id: UUID
  public let startedAt: Date
  public let endedAt: Date?
  public let status: WorkoutSessionStatus
  public let routineVersion: String
  public let results: [ExerciseResult]
  public let usedCamera: Bool

  public init(
    id: UUID = UUID(),
    startedAt: Date,
    endedAt: Date?,
    status: WorkoutSessionStatus,
    routineVersion: String,
    results: [ExerciseResult],
    usedCamera: Bool
  ) {
    self.id = id
    self.startedAt = startedAt
    self.endedAt = endedAt
    self.status = status
    self.routineVersion = routineVersion
    self.results = results
    self.usedCamera = usedCamera
  }

  public var completedAt: Date? {
    status == .completed ? endedAt : nil
  }

  public var duration: TimeInterval? {
    guard let endedAt else { return nil }
    return max(0, endedAt.timeIntervalSince(startedAt))
  }

  public var targetRepetitions: Int {
    results.reduce(0) { $0 + $1.targetReps }
  }

  public var completedRepetitions: Int {
    results.reduce(0) { $0 + $1.completedReps }
  }
}
