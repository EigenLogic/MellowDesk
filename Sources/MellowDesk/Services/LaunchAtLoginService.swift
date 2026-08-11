import Combine
import Foundation
import ServiceManagement

enum LaunchAtLoginState: Equatable {
  case disabled
  case enabled
  case requiresApproval
  case notFound

  var isEnabled: Bool {
    self == .enabled
  }
}

@available(macOS 13.0, *)
@MainActor
final class LaunchAtLoginService: ObservableObject {
  @Published private(set) var state: LaunchAtLoginState
  @Published private(set) var lastErrorDescription: String?

  private let service: SMAppService

  init(service: SMAppService = .mainApp) {
    self.service = service
    state = Self.map(service.status)
  }

  var isEnabled: Bool {
    state.isEnabled
  }

  func refresh() {
    state = Self.map(service.status)
  }

  @discardableResult
  func setEnabled(_ enabled: Bool) async -> Bool {
    if enabled {
      return register()
    }
    return await unregister()
  }

  @discardableResult
  func register() -> Bool {
    if service.status == .enabled {
      refresh()
      lastErrorDescription = nil
      return true
    }

    do {
      try service.register()
      refresh()
      lastErrorDescription = nil
      return state == .enabled || state == .requiresApproval
    } catch {
      refresh()
      lastErrorDescription = error.localizedDescription
      return false
    }
  }

  @discardableResult
  func unregister() async -> Bool {
    if service.status == .notRegistered {
      refresh()
      lastErrorDescription = nil
      return true
    }

    do {
      try await service.unregister()
      refresh()
      lastErrorDescription = nil
      return state == .disabled
    } catch {
      refresh()
      lastErrorDescription = error.localizedDescription
      return false
    }
  }

  private static func map(_ status: SMAppService.Status) -> LaunchAtLoginState {
    switch status {
    case .notRegistered:
      return .disabled
    case .enabled:
      return .enabled
    case .requiresApproval:
      return .requiresApproval
    case .notFound:
      return .notFound
    @unknown default:
      return .notFound
    }
  }
}
