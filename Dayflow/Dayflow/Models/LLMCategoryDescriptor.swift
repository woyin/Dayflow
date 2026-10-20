import Foundation

struct LLMCategoryDescriptor: Codable, Equatable, Hashable, Sendable {
  let id: UUID
  let name: String
  let colorHex: String
  let description: String?
  let isSystem: Bool
  let isIdle: Bool
}
