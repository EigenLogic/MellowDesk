import Foundation

public struct ActivityCompletion: Identifiable, Codable, Equatable, Sendable {
  public let id: UUID
  public let activity: WellnessActivityKind
  public let completedAt: Date
  public let sourceID: String?

  public init(
    id: UUID = UUID(),
    activity: WellnessActivityKind,
    completedAt: Date,
    sourceID: String? = nil
  ) {
    self.id = id
    self.activity = activity
    self.completedAt = completedAt
    self.sourceID = sourceID
  }
}
