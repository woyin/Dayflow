//
//  LegacyAccountCleanup.swift
//  Dayflow
//
//  Dayflow no longer has accounts or paid plans. This removes the session
//  token and account settings that earlier versions stored on this Mac.
//

import Foundation
import Security

enum LegacyAccountCleanup {
  private static let sessionService = "com.teleportlabs.dayflow.auth"
  private static let sessionAccount = "session_token"
  private static let defaultsKeys = [
    "dayflowAccountEmail",
    "dayflowPendingReferralCode",
    "dayflowAnalyticsAliasedUserId",
    "dayflowProviderEndpointV2",
    "dayflowBackendAuthTokenOverride",
    "localBackendAuthFallbackToken",
  ]

  static func run(defaults: UserDefaults = .standard) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: sessionService,
      kSecAttrAccount as String: sessionAccount,
    ]
    SecItemDelete(query as CFDictionary)
    defaultsKeys.forEach { defaults.removeObject(forKey: $0) }
  }
}
