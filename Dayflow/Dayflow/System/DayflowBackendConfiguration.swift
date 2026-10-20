import Foundation

enum DayflowBackendConfiguration {
  static let infoPlistEndpointKey = "DayflowBackendURL"
  static let debugOverrideDefaultsKey = "dayflowBackendURLOverride"

  static func endpoint(
    bundle: Bundle = .main,
    defaults: UserDefaults = .standard
  ) -> String? {
    #if DEBUG
      if let override = normalized(defaults.string(forKey: debugOverrideDefaultsKey)) {
        return override
      }
    #endif

    return normalized(bundle.infoDictionary?[infoPlistEndpointKey] as? String)
  }

  private static func normalized(_ rawValue: String?) -> String? {
    guard let rawValue else { return nil }

    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }

    return trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
  }
}
