import Foundation
import XCTest

@testable import MellowDesk

@MainActor
final class AppSettingsTests: XCTestCase {
  func testPelvicFloorTrainingIsEnabledByDefault() {
    XCTAssertTrue(AppSettings.default.pelvicFloorTrainingEnabled)
    XCTAssertTrue(AppSettings().pelvicFloorTrainingEnabled)
  }

  func testSettingsStoreEnablesPelvicFloorTrainingForLegacySettings() throws {
    let context = try makeDefaultsContext()
    defer { context.remove() }
    context.defaults.set(Data("{}".utf8), forKey: SettingsStore.storageKey)

    let store = SettingsStore(defaults: context.defaults)

    XCTAssertTrue(store.settings.pelvicFloorTrainingEnabled)
  }

  func testSettingsStorePreservesExplicitlyDisabledPelvicFloorTraining() throws {
    let context = try makeDefaultsContext()
    defer { context.remove() }
    let data = try JSONEncoder().encode(
      AppSettings(pelvicFloorTrainingEnabled: false)
    )
    context.defaults.set(data, forKey: SettingsStore.storageKey)

    let store = SettingsStore(defaults: context.defaults)

    XCTAssertFalse(store.settings.pelvicFloorTrainingEnabled)
  }

  func testMenuHeightIncludesEnabledPelvicFloorEntry() {
    var disabledSettings = AppSettings.default
    disabledSettings.pelvicFloorTrainingEnabled = false

    XCTAssertEqual(
      MenuBarContentView.contentSize(for: AppSettings.default).height,
      MenuBarContentView.contentSize(for: disabledSettings).height
        + MenuBarContentView.pelvicFloorRowHeight
    )
  }

  private func makeDefaultsContext() throws -> DefaultsContext {
    let suiteName = "cn.eigenlogic.mellowdesk.tests.app-settings.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return DefaultsContext(defaults: defaults, suiteName: suiteName)
  }

  private struct DefaultsContext {
    let defaults: UserDefaults
    let suiteName: String

    func remove() {
      defaults.removePersistentDomain(forName: suiteName)
    }
  }
}
