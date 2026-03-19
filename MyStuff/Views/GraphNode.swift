import Foundation
import CoreGraphics

enum GraphNodeKind: Equatable {
    case topCategory(Category)
    case subCategory(Category)
    case item(Item)
    case overflow(count: Int)
}

struct GraphNode: Identifiable {
    let id: String
    let kind: GraphNodeKind
    var position: CGPoint  // normalized 800×600 space
    var parentId: String?  // id of the node this was expanded from
}

struct GraphEdge: Identifiable {
    let id: String  // "\(from)-\(to)"
    let from: String
    let to: String
}
