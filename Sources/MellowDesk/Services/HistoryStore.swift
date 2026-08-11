import Combine
import Foundation
import MellowDeskCore

@MainActor
final class HistoryStore: ObservableObject {
  private struct Archive: Codable {
    let schemaVersion: Int
    let sessions: [WorkoutSession]

    init(sessions: [WorkoutSession]) {
      schemaVersion = 1
      self.sessions = sessions
    }
  }

  enum StoreError: LocalizedError {
    case sessionHasNotEnded

    var errorDescription: String? {
      switch self {
      case .sessionHasNotEnded:
        return "Only ended workout sessions can be written to history."
      }
    }
  }

  static let directoryName = "MellowDesk"
  static let fileName = "workout-history.json"

  @Published private(set) var sessions: [WorkoutSession] = []
  @Published private(set) var lastErrorDescription: String?
  @Published private(set) var lastRecoveryBackupURL: URL?

  let fileURL: URL

  private let fileManager: FileManager
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  convenience init(fileManager: FileManager = .default) {
    let applicationSupport =
      fileManager.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first ?? fileManager.temporaryDirectory
    let fileURL =
      applicationSupport
      .appendingPathComponent(Self.directoryName, isDirectory: true)
      .appendingPathComponent(Self.fileName, isDirectory: false)
    self.init(fileURL: fileURL, fileManager: fileManager)
  }

  init(fileURL: URL, fileManager: FileManager = .default) {
    self.fileURL = fileURL
    self.fileManager = fileManager

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    self.encoder = encoder

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    self.decoder = decoder

    loadFromDisk()
  }

  /// Appends or replaces an ended session with the same identifier.
  /// The file is persisted before the observable in-memory value changes.
  func append(_ session: WorkoutSession) throws {
    guard session.endedAt != nil else {
      throw StoreError.sessionHasNotEnded
    }

    var updated = sessions
    if let index = updated.firstIndex(where: { $0.id == session.id }) {
      updated[index] = session
    } else {
      updated.append(session)
    }
    updated.sort(by: Self.sortChronologically)

    try write(updated)
    sessions = updated
    lastErrorDescription = nil
  }

  func recent(limit: Int = 20) -> [WorkoutSession] {
    guard limit > 0 else { return [] }
    return Array(sessions.suffix(limit).reversed())
  }

  func recentCompleted(limit: Int = 20) -> [WorkoutSession] {
    guard limit > 0 else { return [] }
    return Array(
      sessions.lazy
        .reversed()
        .filter { $0.status == .completed }
        .prefix(limit)
    )
  }

  /// Uses a half-open date interval: `start <= endedAt < end`.
  func sessions(from start: Date, to end: Date) -> [WorkoutSession] {
    guard start < end else { return [] }
    return sessions.filter { session in
      guard let endedAt = session.endedAt else { return false }
      return endedAt >= start && endedAt < end
    }
  }

  func sessions(on day: Date, calendar: Calendar = .current) -> [WorkoutSession] {
    guard
      let interval = calendar.dateInterval(of: .day, for: day)
    else {
      return []
    }
    return sessions(from: interval.start, to: interval.end)
  }

  func completedSessions(from start: Date, to end: Date) -> [WorkoutSession] {
    sessions(from: start, to: end).filter { $0.status == .completed }
  }

  func clear() throws {
    try write([])
    sessions = []
    lastErrorDescription = nil
  }

  func reload() {
    loadFromDisk()
  }

  private func loadFromDisk() {
    guard fileManager.fileExists(atPath: fileURL.path) else {
      sessions = []
      lastErrorDescription = nil
      return
    }

    do {
      let data = try Data(contentsOf: fileURL)
      let decoded: [WorkoutSession]
      if let archive = try? decoder.decode(Archive.self, from: data) {
        decoded = archive.sessions
      } else {
        // Supports the early unversioned on-disk shape.
        decoded = try decoder.decode([WorkoutSession].self, from: data)
      }
      sessions = decoded.sorted(by: Self.sortChronologically)
      lastErrorDescription = nil
    } catch {
      recoverFromCorruptFile(originalError: error)
    }
  }

  private func recoverFromCorruptFile(originalError: Error) {
    do {
      let backupURL = uniqueCorruptBackupURL()
      try fileManager.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try fileManager.moveItem(at: fileURL, to: backupURL)
      lastRecoveryBackupURL = backupURL
      sessions = []
      try write([])
      lastErrorDescription =
        "History was reset after invalid data was backed up to \(backupURL.lastPathComponent)."
    } catch {
      sessions = []
      lastErrorDescription =
        "Could not recover workout history: \(originalError.localizedDescription); backup error: \(error.localizedDescription)"
    }
  }

  private func write(_ sessions: [WorkoutSession]) throws {
    try fileManager.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let data = try encoder.encode(Archive(sessions: sessions))
    try data.write(to: fileURL, options: .atomic)
  }

  private func uniqueCorruptBackupURL() -> URL {
    let timestamp = Int(Date().timeIntervalSince1970 * 1_000)
    let name = "workout-history.corrupt-\(timestamp)-\(UUID().uuidString).json"
    return fileURL.deletingLastPathComponent().appendingPathComponent(name)
  }

  private static func sortChronologically(_ lhs: WorkoutSession, _ rhs: WorkoutSession) -> Bool {
    let lhsDate = lhs.endedAt ?? lhs.startedAt
    let rhsDate = rhs.endedAt ?? rhs.startedAt
    if lhsDate == rhsDate {
      return lhs.id.uuidString < rhs.id.uuidString
    }
    return lhsDate < rhsDate
  }
}
