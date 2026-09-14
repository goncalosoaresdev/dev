import Foundation

struct ClipboardItem: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let text: String
    let createdAt: Date
}
