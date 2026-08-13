import Foundation

extension Notification.Name {
  /// Posted on the main actor after the reminder body or primary action is selected.
  /// `object` contains the durable reminder occurrence identifier.
  static let mellowDeskStartActivityRequested = Notification.Name(
    "cn.eigenlogic.mellowdesk.notification.start-activity-requested"
  )
}

protocol WorkoutPresentationRequesting: AnyObject {
  @MainActor func requestWorkoutPresentation()
}
