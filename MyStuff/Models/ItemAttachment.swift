import Foundation

struct ItemAttachment: Identifiable, Equatable {
    let id: String
    let itemId: String
    let driveFileId: String
    var kind: Kind
    var displayName: String
    let createdAt: String

    enum Kind: String, CaseIterable, Identifiable {
        case invoice
        case userManual
        case other

        var id: String { rawValue }

        var displayTitle: String {
            switch self {
            case .invoice: return "Invoice"
            case .userManual: return "User Manual"
            case .other: return "Other"
            }
        }
    }

    init(
        id: String = UUID().uuidString,
        itemId: String,
        driveFileId: String,
        kind: Kind = .other,
        displayName: String = "",
        createdAt: String = ""
    ) {
        self.id = id
        self.itemId = itemId
        self.driveFileId = driveFileId
        self.kind = kind
        self.displayName = displayName
        self.createdAt = createdAt.isEmpty ? ISO8601DateFormatter().string(from: Date()) : createdAt
    }

    static let columnOrder = ["id", "itemId", "driveFileId", "kind", "displayName", "createdAt"]
}
