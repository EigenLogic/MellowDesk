import Foundation

enum AppFormatters {
  static let time: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    return formatter
  }()

  static let dateTime: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
  }()

  static let relative: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.locale = .current
    formatter.unitsStyle = .full
    return formatter
  }()

  static func duration(seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds.rounded()))
    let minutes = total / 60
    let remainder = total % 60
    if minutes == 0 { return "\(remainder) 秒" }
    return "\(minutes) 分 \(remainder) 秒"
  }
}
