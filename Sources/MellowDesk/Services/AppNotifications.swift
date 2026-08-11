import Foundation

extension Notification.Name {
  /// Posted on the main actor after the reminder body or "Start workout" action is selected.
  /// The app shell should observe this and present the workout window.
  static let mellowDeskStartWorkoutRequested = Notification.Name(
    "cn.eigenlogic.mellowdesk.notification.start-workout-requested"
  )
}

protocol WorkoutPresentationRequesting: AnyObject {
  @MainActor func requestWorkoutPresentation()
}
