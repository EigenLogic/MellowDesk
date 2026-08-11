import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
  static let storageKey = "cn.eigenlogic.mellowdesk.app-settings.v1"

  @Published private(set) var settings: AppSettings

  private let defaults: UserDefaults
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    encoder = JSONEncoder()
    decoder = JSONDecoder()

    if let data = defaults.data(forKey: Self.storageKey),
      var decoded = try? decoder.decode(AppSettings.self, from: data)
    {
      decoded.normalize()
      settings = decoded
    } else {
      settings = .default
    }
  }

  func update(_ change: (inout AppSettings) -> Void) {
    var updated = settings
    change(&updated)
    updated.normalize()
    settings = updated
    persist()
  }

  func replace(with settings: AppSettings) {
    var normalized = settings
    normalized.normalize()
    self.settings = normalized
    persist()
  }

  func pause(until date: Date) {
    update { $0.pauseUntil = date }
  }

  func resume() {
    update { $0.pauseUntil = nil }
  }

  func reset() {
    settings = .default
    persist()
  }

  private func persist() {
    guard let data = try? encoder.encode(settings) else { return }
    defaults.set(data, forKey: Self.storageKey)
  }
}
