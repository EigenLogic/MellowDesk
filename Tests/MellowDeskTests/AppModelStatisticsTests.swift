import Foundation
import MellowDeskCore
import UserNotifications
import XCTest

@testable import MellowDesk

@MainActor
final class AppModelStatisticsTests: XCTestCase {
  func testPelvicFloorCompletionAppearsInCountsTrendAndRecentHistory() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("mellowdesk-app-model-tests-\(UUID().uuidString)")
    let suiteName = "cn.eigenlogic.mellowdesk.app-model-tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
      try? FileManager.default.removeItem(at: directory)
      defaults.removePersistentDomain(forName: suiteName)
    }

    let activityStore = ActivityHistoryStore(
      fileURL: directory.appendingPathComponent(ActivityHistoryStore.fileName)
    )
    let completion = ActivityCompletion(
      activity: .pelvicFloor,
      completedAt: Date(),
      sourceID: "pelvic-statistics"
    )
    try activityStore.append(completion)
    let appModel = AppModel(
      settingsStore: SettingsStore(defaults: defaults),
      historyStore: HistoryStore(
        fileURL: directory.appendingPathComponent(HistoryStore.fileName)
      ),
      activityHistoryStore: activityStore,
      reminderScheduler: ReminderScheduler(
        notificationClient: StatisticsNotificationClient(),
        defaults: defaults
      )
    )

    XCTAssertEqual(appModel.todayCount(for: .pelvicFloor), 1)
    XCTAssertEqual(appModel.todayCompletedCount, 1)
    XCTAssertEqual(appModel.dailyCompletions(days: 1, activity: .pelvicFloor).map(\.count), [1])
    XCTAssertEqual(appModel.recentWellnessItems(limit: 1).first?.activity, .pelvicFloor)
  }
}

@MainActor
private final class StatisticsNotificationClient: ReminderNotificationClient {
  func setDelegate(_ delegate: (any UNUserNotificationCenterDelegate)?) {}
  func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {}
  func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { true }
  func authorizationStatus() async -> UNAuthorizationStatus { .authorized }
  func add(_ request: UNNotificationRequest) async throws {}
  func pendingRequestIdentifiers() async -> Set<String> { [] }
  func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {}
  func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {}
}
