import Combine
import Foundation
import MellowDeskCore

/// Persists lightweight acknowledgements for water, stand-up, and pelvic-floor reminders.
/// Neck-exercise sessions remain owned by `HistoryStore` and its richer workout schema.
@MainActor
final class ActivityHistoryStore: ObservableObject {
  private struct Archive: Codable {
    let schemaVersion: Int
    let completions: [ActivityCompletion]

    init(completions: [ActivityCompletion]) {
      schemaVersion = 1
      self.completions = completions
    }
  }

  enum StoreError: LocalizedError, Equatable {
    case unsupportedActivity(WellnessActivityKind)

    var errorDescription: String? {
      switch self {
      case .unsupportedActivity:
        return "This activity cannot be written to lightweight activity history."
      }
    }
  }

  static let directoryName = "MellowDesk"
  static let fileName = "wellness-history.json"

  @Published private(set) var completions: [ActivityCompletion] = []
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

  /// Appends or replaces an activity completion with the same identifier or source.
  /// The file is persisted before the observable in-memory value changes.
  func append(_ completion: ActivityCompletion) throws {
    guard completion.activity.usesLightweightHistory else {
      throw StoreError.unsupportedActivity(completion.activity)
    }

    var updated = completions
    if let index = updated.firstIndex(where: { stored in
      if stored.id == completion.id { return true }
      guard let sourceID = completion.sourceID else { return false }
      return stored.activity == completion.activity && stored.sourceID == sourceID
    }) {
      updated[index] = completion
    } else {
      updated.append(completion)
    }
    updated.sort(by: Self.sortChronologically)

    try write(updated)
    completions = updated
    lastErrorDescription = nil
  }

  func recent(limit: Int = 20) -> [ActivityCompletion] {
    guard limit > 0 else { return [] }
    return Array(completions.suffix(limit).reversed())
  }

  /// Uses a half-open date interval: `start <= completedAt < end`.
  func completions(from start: Date, to end: Date) -> [ActivityCompletion] {
    guard start < end else { return [] }
    return completions.filter { completion in
      completion.completedAt >= start && completion.completedAt < end
    }
  }

  func completions(on day: Date, calendar: Calendar = .current) -> [ActivityCompletion] {
    guard let interval = calendar.dateInterval(of: .day, for: day) else { return [] }
    return completions(from: interval.start, to: interval.end)
  }

  func clear() throws {
    try write([])
    completions = []
    lastErrorDescription = nil
  }

  func reload() {
    loadFromDisk()
  }

  private func loadFromDisk() {
    guard fileManager.fileExists(atPath: fileURL.path) else {
      completions = []
      lastErrorDescription = nil
      return
    }

    do {
      let data = try Data(contentsOf: fileURL)
      let decoded: [ActivityCompletion]
      if let archive = try? decoder.decode(Archive.self, from: data) {
        decoded = archive.completions
      } else {
        decoded = try decoder.decode([ActivityCompletion].self, from: data)
      }
      completions =
        decoded
        .filter(\.activity.usesLightweightHistory)
        .sorted(by: Self.sortChronologically)
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
      completions = []
      try write([])
      lastErrorDescription =
        "Activity history was reset after invalid data was backed up to \(backupURL.lastPathComponent)."
    } catch {
      completions = []
      lastErrorDescription =
        "Could not recover activity history: \(originalError.localizedDescription); backup error: \(error.localizedDescription)"
    }
  }

  private func write(_ completions: [ActivityCompletion]) throws {
    try fileManager.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let data = try encoder.encode(Archive(completions: completions))
    try data.write(to: fileURL, options: .atomic)
  }

  private func uniqueCorruptBackupURL() -> URL {
    let timestamp = Int(Date().timeIntervalSince1970 * 1_000)
    let name = "wellness-history.corrupt-\(timestamp)-\(UUID().uuidString).json"
    return fileURL.deletingLastPathComponent().appendingPathComponent(name)
  }

  private static func sortChronologically(
    _ lhs: ActivityCompletion,
    _ rhs: ActivityCompletion
  ) -> Bool {
    if lhs.completedAt == rhs.completedAt {
      return lhs.id.uuidString < rhs.id.uuidString
    }
    return lhs.completedAt < rhs.completedAt
  }
}
