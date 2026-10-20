import Foundation

// Stand-ins for app symbols whose real files import GRDB or Sentry, which this
// package does not link. Keep these in step with StorageDateHelpers.swift.
extension DateFormatter {
  static let yyyyMMdd: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.timeZone = Calendar.current.timeZone
    return formatter
  }()
}
