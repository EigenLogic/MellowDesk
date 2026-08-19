import Foundation
import MellowDeskCore

struct WellnessHistoryItem: Identifiable, Equatable {
  let id: String
  let activity: WellnessActivityKind
  let completedAt: Date
  let detail: String
}

extension WellnessActivityKind {
  var localizedName: String {
    switch self {
    case .stand:
      return "起身活动"
    case .water:
      return "喝水"
    case .neck:
      return "颈肩微运动"
    case .pelvicFloor:
      return "提肛跟练"
    }
  }

  var completionTitle: String {
    switch self {
    case .stand:
      return "完成一次起身活动"
    case .water:
      return "完成一次喝水打卡"
    case .neck:
      return "完成一组颈肩微运动"
    case .pelvicFloor:
      return "完成一组提肛跟练"
    }
  }

  var systemImage: String {
    switch self {
    case .stand:
      return "figure.walk"
    case .water:
      return "drop.fill"
    case .neck:
      return "figure.mind.and.body"
    case .pelvicFloor:
      return "slowmo"
    }
  }
}
