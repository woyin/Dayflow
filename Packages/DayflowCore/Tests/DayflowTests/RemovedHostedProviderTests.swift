import Foundation
import Testing

@testable import Dayflow

// Swift Testing (not XCTest) so these run with the command-line toolchain:
//   swift test --package-path Packages/DayflowCore
// The XCTest suites in Dayflow/DayflowTests still run in Xcode.
struct RemovedHostedProviderTests {
  private func makeDefaults() throws -> UserDefaults {
    let suite = "Dayflow.PackageTests.\(UUID().uuidString)"
    return try #require(UserDefaults(suiteName: suite))
  }

  @Test func storedRoutingNamingRemovedPrimaryFallsBackToGemini() throws {
    let defaults = try makeDefaults()
    defaults.set(
      Data(#"{"schemaVersion":2,"primary":"dayflow","secondary":"claude"}"#.utf8),
      forKey: LLMProviderRoutingStore.storageKey)

    let routing = try LLMProviderRoutingStore.load(from: defaults)

    #expect(routing == LLMProviderRouting(primary: .gemini, secondary: .claude))
  }

  @Test func storedRoutingNamingRemovedSecondaryDropsIt() throws {
    let defaults = try makeDefaults()
    defaults.set(
      Data(#"{"schemaVersion":2,"primary":"gemini","secondary":"dayflow"}"#.utf8),
      forKey: LLMProviderRoutingStore.storageKey)

    #expect(try LLMProviderRoutingStore.load(from: defaults) == LLMProviderRouting(primary: .gemini))
  }

  @Test func legacySelectedProviderDayflowMapsToDefault() throws {
    let defaults = try makeDefaults()
    defaults.set("dayflow", forKey: LegacyLLMProviderMigration.Key.selectedProvider)

    #expect(LegacyLLMProviderMigration.migrate(from: defaults).routing.primary == .gemini)
  }

  @Test func legacyBackendEnumJSONFallsBackToDefault() throws {
    let defaults = try makeDefaults()
    defaults.set(
      Data(#"{"dayflowBackend":{"endpoint":"https://example.com"}}"#.utf8),
      forKey: LegacyLLMProviderMigration.Key.providerType)

    #expect(LegacyLLMProviderMigration.migrate(from: defaults).routing.primary == .gemini)
  }

  @Test func storedDailyProviderFromRemovedServiceDecodesAsNone() throws {
    let decoded = try JSONDecoder().decode(
      [DailyRecapProvider].self, from: Data(#"["dayflow","claude"]"#.utf8))

    #expect(decoded == [.none, .claude])
  }

  @Test func providerListNoLongerOffersHostedService() {
    #expect(!LLMProviderID.allCases.map(\.rawValue).contains("dayflow"))
    #expect(!DailyRecapProvider.allCases.map(\.rawValue).contains("dayflow"))
  }
}
