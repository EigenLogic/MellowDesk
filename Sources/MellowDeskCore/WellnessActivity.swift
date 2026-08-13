import Foundation

public enum WellnessActivityKind: String, Codable, CaseIterable, Hashable, Sendable {
  case stand
  case water
  case neck

  public var isQuickActivity: Bool {
    switch self {
    case .stand, .water:
      return true
    case .neck:
      return false
    }
  }
}

/// The default workday rotation. A monotonically increasing cycle index can be persisted
/// by the scheduler; this type maps it to one of the three activity slots.
public struct WellnessPlan: Equatable, Sendable {
  public static let cycleLength = 3

  public static func normalizedSlot(_ slot: Int) -> Int {
    let remainder = slot % cycleLength
    return remainder >= 0 ? remainder : remainder + cycleLength
  }

  public static func activity(for slot: Int) -> WellnessActivityKind {
    switch normalizedSlot(slot) {
    case 0:
      return .stand
    case 1:
      return .water
    default:
      return .neck
    }
  }
}
