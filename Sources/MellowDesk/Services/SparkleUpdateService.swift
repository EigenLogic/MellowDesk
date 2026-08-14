import Combine
import Foundation
import Sparkle

/// Owns Sparkle for the lifetime of the app and keeps update preferences in
/// Sparkle's user defaults instead of duplicating them in `AppSettings`.
@MainActor
final class SparkleUpdateService: NSObject, ObservableObject, SPUUpdaterDelegate {
  @Published private(set) var readyUpdateVersion: String?

  private var updaterController: SPUStandardUpdaterController!
  private var immediateInstallationHandler: (() -> Void)?
  private var didStart = false

  override init() {
    super.init()
    updaterController = SPUStandardUpdaterController(
      startingUpdater: false,
      updaterDelegate: self,
      userDriverDelegate: nil
    )
  }

  var automaticUpdatesEnabled: Bool {
    let updater = updaterController.updater
    return updater.automaticallyChecksForUpdates && updater.automaticallyDownloadsUpdates
  }

  var currentVersionDisplayText: String {
    let releaseVersion =
      Bundle.main.object(forInfoDictionaryKey: "MellowDeskReleaseVersion") as? String
    if let releaseVersion, !releaseVersion.isEmpty {
      return releaseVersion
    }
    if let appVersion =
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
      !appVersion.isEmpty
    {
      return appVersion
    }
    return "未知"
  }

  func start() {
    guard !didStart else { return }
    didStart = true
    updaterController.startUpdater()
  }

  func setAutomaticUpdatesEnabled(_ enabled: Bool) {
    objectWillChange.send()
    let updater = updaterController.updater
    if enabled {
      updater.automaticallyChecksForUpdates = true
      updater.automaticallyDownloadsUpdates = true
    } else {
      updater.automaticallyDownloadsUpdates = false
      updater.automaticallyChecksForUpdates = false
    }
  }

  func checkForUpdates() {
    updaterController.checkForUpdates(nil)
  }

  func installReadyUpdate() {
    guard let immediateInstallationHandler else { return }
    self.immediateInstallationHandler = nil
    readyUpdateVersion = nil
    AppWindowCoordinator.shared.dismissUpdateReadyPrompt()
    AppWindowCoordinator.shared.clearUpdateReadyStatus()
    immediateInstallationHandler()
  }

  func updater(
    _ updater: SPUUpdater,
    willInstallUpdateOnQuit item: SUAppcastItem,
    immediateInstallationBlock: @escaping () -> Void
  ) -> Bool {
    immediateInstallationHandler = immediateInstallationBlock
    readyUpdateVersion = item.displayVersionString
    AppWindowCoordinator.shared.showUpdateReadyPrompt(version: item.displayVersionString)
    return true
  }
}
