import Foundation

public enum WellnessActivityKind: String, Codable, CaseIterable, Hashable, Sendable {
  case stand
  case water
  case neck
  case pelvicFloor

  public var isQuickActivity: Bool {
    switch self {
    case .stand, .water:
      return true
    case .neck, .pelvicFloor:
      return false
    }
  }

  public var usesLightweightHistory: Bool {
    self != .neck
  }
}

/// The default workday rotation. A monotonically increasing cycle index can be persisted
/// by the scheduler; this type maps it to one of the four activity slots.
public struct WellnessPlan: Equatable, Sendable {
  public static let cycleLength = 4
  public static let legacyNeckSlot = 2

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
    case legacyNeckSlot:
      return .neck
    default:
      return .pelvicFloor
    }
  }
}
