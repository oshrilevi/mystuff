import SwiftUI

struct NodeGraphView: View {
    @EnvironmentObject var session: Session
    @Binding var viewMode: ItemViewMode
    @AppStorage("thumbnailSize") private var thumbnailSizeRaw: String = ThumbnailSize.medium.rawValue

    @State private var nodes: [GraphNode] = []
    @State private var edges: [GraphEdge] = []
    @State private var expandedTopId: String? = nil
    @State private var expandedSubId: String? = nil
    @State private var selectedItem: Item? = nil

    // Pan state
    @State private var panOffset: CGSize = .zero
    @State private var panDragStart: CGSize = .zero

    // Zoom state
    @State private var scale: CGFloat = 1.0
    @State private var scaleStart: CGFloat = 1.0

    // Node drag state
    @State private var draggingNodeId: String? = nil
    @State private var dragStartNodePos: CGPoint = .zero

    // Original positions before a node was moved to center on expand
    @State private var nodeOriginalPositions: [String: CGPoint] = [:]

    private var categoriesVM: CategoriesViewModel { session.categories }
    private var inventory: InventoryViewModel { session.inventory }

    private var displayChoiceBinding: Binding<ItemsDisplayChoice> {
        Binding(
            get: {
                if viewMode == .list { return .list }
                if viewMode == .graph { return .graph }
                return ItemsDisplayChoice(rawValue: thumbnailSizeRaw) ?? .gridMedium
            },
            set: { choice in
                if choice == .list {
                    viewMode = .list
                } else if choice == .graph {
                    viewMode = .graph
                } else {
                    viewMode = .grid
                    thumbnailSizeRaw = choice.thumbnailSizeRaw
                }
            }
        )
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background — pan gesture + tap to collapse
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { collapseAll() }
                    .gesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { value in
                                panOffset = CGSize(
                                    width: panDragStart.width + value.translation.width,
                                    height: panDragStart.height + value.translation.height
                                )
                            }
                            .onEnded { _ in panDragStart = panOffset }
                    )
                    .gesture(magnificationGesture)

                // Edge layer
                Canvas { context, size in
                    context.translateBy(x: size.width / 2 + panOffset.width, y: size.height / 2 + panOffset.height)
                    context.scaleBy(x: scale, y: scale)
                    context.translateBy(x: -size.width / 2, y: -size.height / 2)
                    drawEdges(context: &context, size: size)
                }
                .allowsHitTesting(false)

                // Node layer
                ForEach(nodes) { node in
                    nodeView(for: node, deemphasized: isDeemphasized(node))
                        .position(screenPosition(for: node, in: geo.size))
                        .onTapGesture { handleTap(node) }
                        .gesture(nodeDragGesture(for: node, canvasSize: geo.size))
                        .transition(.scale.combined(with: .opacity))
                        .cursor(.pointingHand)
                }
            }
            .background(
                ScrollCapture { delta in
                    panOffset.width += delta.width
                    panOffset.height += delta.height
                    panDragStart = panOffset
                }
            )
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("Display", selection: displayChoiceBinding) {
                    ForEach(ItemsDisplayChoice.allCases, id: \.rawValue) { choice in
                        Image(systemName: choice.icon).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
                .help("Display: Compact, Medium, Large, or List")
                HStack(spacing: 16) {
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            panOffset = .zero
                            panDragStart = .zero
                            scale = 1.0
                            scaleStart = 1.0
                        }
                    } label: {
                        Image(systemName: "scope")
                    }
                    .help("Reset view to center")
                    .disabled(panOffset == .zero && scale == 1.0)
                    Rectangle()
                        .fill(.tertiary)
                        .frame(width: 1, height: 20)
                    UserAvatarMenuView()
                }
            }
        }
        .onAppear { buildInitial() }
        .onChange(of: categoriesVM.categories) { _, _ in
            if expandedTopId == nil { buildInitial() }
        }
        .sheet(item: $selectedItem) { item in
            ItemDetailView(item: item, onDismiss: { selectedItem = nil })
                .environmentObject(session)
        }
        .navigationTitle("Graph")
    }

    // MARK: - Positioning

    private func screenPosition(for node: GraphNode, in canvasSize: CGSize) -> CGPoint {
        let p = GraphLayoutEngine.scale(node.position, to: canvasSize)
        let cx = canvasSize.width / 2
        let cy = canvasSize.height / 2
        return CGPoint(
            x: (p.x - cx) * scale + cx + panOffset.width,
            y: (p.y - cy) * scale + cy + panOffset.height
        )
    }

    // MARK: - Zoom gesture

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = max(0.2, min(5.0, scaleStart * value))
            }
            .onEnded { value in
                scale = max(0.2, min(5.0, scaleStart * value))
                scaleStart = scale
            }
    }

    // MARK: - Node drag gesture

    private func nodeDragGesture(for node: GraphNode, canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if draggingNodeId != node.id {
                    draggingNodeId = node.id
                    dragStartNodePos = node.position
                }
                let dx = value.translation.width * GraphLayoutEngine.canvasSize.width / (canvasSize.width * scale)
                let dy = value.translation.height * GraphLayoutEngine.canvasSize.height / (canvasSize.height * scale)
                if let idx = nodes.firstIndex(where: { $0.id == node.id }) {
                    nodes[idx].position = CGPoint(x: dragStartNodePos.x + dx, y: dragStartNodePos.y + dy)
                }
            }
            .onEnded { _ in
                draggingNodeId = nil
            }
    }

    // MARK: - Build

    private func buildInitial() {
        let tops = categoriesVM.topLevelCategories
        let positions = GraphLayoutEngine.topLevelPositions(count: tops.count)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            nodes = zip(tops, positions).map { cat, pos in
                GraphNode(id: cat.id, kind: .topCategory(cat), position: pos, parentId: nil)
            }
            edges = []
            expandedTopId = nil
            expandedSubId = nil
            nodeOriginalPositions = [:]
        }
    }

    // MARK: - Tap handling

    private func handleTap(_ node: GraphNode) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            switch node.kind {
            case .topCategory(let cat):
                if expandedTopId == cat.id {
                    collapseTop()
                } else {
                    collapseTop()
                    expandTop(cat)
                }
            case .subCategory(let cat):
                if expandedSubId == cat.id {
                    collapseSub()
                } else {
                    collapseSub()
                    expandSub(cat)
                }
            case .item(let item):
                selectedItem = item
            case .overflow:
                break
            }
        }
    }

    // MARK: - Expand

    private func expandTop(_ category: Category) {
        guard let idx = nodes.firstIndex(where: { $0.id == category.id }) else { return }
        // Save original ring position and slide node to canvas center
        nodeOriginalPositions[category.id] = nodes[idx].position
        nodes[idx].position = GraphLayoutEngine.center
        let children = categoriesVM.childrenByParentId[category.id] ?? []
        if children.isEmpty {
            let items = inventory.items.filter { $0.categoryId == category.id }
            appendItemNodes(parentId: category.id, parentPos: GraphLayoutEngine.center, items: items)
        } else {
            let positions = GraphLayoutEngine.circularItemPositions(
                parentPos: GraphLayoutEngine.center,
                count: children.count
            )
            let newNodes = zip(children, positions).map { cat, pos in
                GraphNode(id: cat.id, kind: .subCategory(cat), position: pos, parentId: category.id)
            }
            let newEdges = children.map { cat in
                GraphEdge(id: "\(category.id)-\(cat.id)", from: category.id, to: cat.id)
            }
            nodes.append(contentsOf: newNodes)
            edges.append(contentsOf: newEdges)
        }
        expandedTopId = category.id
    }

    private func expandSub(_ category: Category) {
        guard let subIdx = nodes.firstIndex(where: { $0.id == category.id }) else { return }
        let subPos = nodes[subIdx].position
        // Find the parent's current position to compute the outward vector
        let parentPos: CGPoint = nodes[subIdx].parentId
            .flatMap { pid in nodes.first(where: { $0.id == pid }) }
            .map(\.position) ?? GraphLayoutEngine.center
        // Push the subcategory further along the parent→child vector
        let dx = subPos.x - parentPos.x
        let dy = subPos.y - parentPos.y
        let dist = sqrt(dx * dx + dy * dy)
        let newPos: CGPoint
        if dist > 0 {
            let push = GraphLayoutEngine.minItemRingRadius
            newPos = CGPoint(x: subPos.x + dx / dist * push, y: subPos.y + dy / dist * push)
        } else {
            newPos = subPos
        }
        nodeOriginalPositions[category.id] = subPos
        nodes[subIdx].position = newPos
        let items = inventory.items.filter { $0.categoryId == category.id }
        appendItemNodes(parentId: category.id, parentPos: newPos, items: items)
        expandedSubId = category.id
    }

    private func appendItemNodes(parentId: String, parentPos: CGPoint, items: [Item]) {
        guard !items.isEmpty else { return }
        let positions = GraphLayoutEngine.circularItemPositions(parentPos: parentPos, count: items.count)
        let newNodes = zip(items, positions).map { item, pos in
            GraphNode(id: item.id, kind: .item(item), position: pos, parentId: parentId)
        }
        let newEdges = newNodes.map { node in
            GraphEdge(id: "\(parentId)-\(node.id)", from: parentId, to: node.id)
        }
        nodes.append(contentsOf: newNodes)
        edges.append(contentsOf: newEdges)
    }

    // MARK: - Collapse

    private func collapseTop() {
        guard let topId = expandedTopId else { return }
        // Collapse sub without bringing top back to center — we're about to restore top to ring
        if let subId = expandedSubId {
            removeDescendants(of: subId)
            if let subIdx = nodes.firstIndex(where: { $0.id == subId }),
               let orig = nodeOriginalPositions[subId] {
                nodes[subIdx].position = orig
            }
            nodeOriginalPositions.removeValue(forKey: subId)
            expandedSubId = nil
        }
        removeDescendants(of: topId)
        // Restore top category to its original ring position
        if let topIdx = nodes.firstIndex(where: { $0.id == topId }),
           let orig = nodeOriginalPositions[topId] {
            nodes[topIdx].position = orig
        }
        nodeOriginalPositions.removeValue(forKey: topId)
        expandedTopId = nil
    }

    private func collapseSub() {
        guard let subId = expandedSubId else { return }
        removeDescendants(of: subId)
        // Restore subcategory to its position around the ring-of-center
        if let subIdx = nodes.firstIndex(where: { $0.id == subId }),
           let orig = nodeOriginalPositions[subId] {
            nodes[subIdx].position = orig
        }
        nodeOriginalPositions.removeValue(forKey: subId)
        expandedSubId = nil
    }

    private func collapseAll() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            collapseTop()
        }
    }

    private func removeDescendants(of parentId: String) {
        let childIds = Set(nodes.filter { $0.parentId == parentId }.map { $0.id })
        let grandChildIds = Set(nodes.filter { n in childIds.contains(n.parentId ?? "") }.map { $0.id })
        let toRemove = childIds.union(grandChildIds)
        nodes.removeAll { toRemove.contains($0.id) }
        edges.removeAll { toRemove.contains($0.from) || toRemove.contains($0.to) }
    }

    // MARK: - De-emphasis

    private func isDeemphasized(_ node: GraphNode) -> Bool {
        guard let topId = expandedTopId else { return false }
        switch node.kind {
        case .topCategory(let cat):
            return cat.id != topId
        case .subCategory(let cat):
            if let subId = expandedSubId {
                return cat.id != subId
            }
            return false
        case .item, .overflow:
            return false
        }
    }

    // MARK: - Edge drawing

    private func drawEdges(context: inout GraphicsContext, size: CGSize) {
        let nodeById = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        for edge in edges {
            guard let fromNode = nodeById[edge.from], let toNode = nodeById[edge.to] else { continue }
            let from = GraphLayoutEngine.scale(fromNode.position, to: size)
            let to = GraphLayoutEngine.scale(toNode.position, to: size)
            var path = Path()
            path.move(to: from)
            path.addLine(to: to)
            context.stroke(path, with: .color(.secondary.opacity(0.4)), lineWidth: 1.5)
        }
    }

    // MARK: - Node views

    @ViewBuilder
    private func nodeView(for node: GraphNode, deemphasized: Bool) -> some View {
        Group {
            switch node.kind {
            case .topCategory(let cat):
                let children = categoriesVM.childrenByParentId[cat.id] ?? []
                let count = children.isEmpty
                    ? inventory.items.filter { $0.categoryId == cat.id }.count
                    : children.count
                CircleNode(label: cat.name, icon: cat.iconSymbol, size: 52, color: .accentColor, count: count)
            case .subCategory(let cat):
                let count = inventory.items.filter { $0.categoryId == cat.id }.count
                CircleNode(label: cat.name, icon: cat.iconSymbol, size: 40, color: .accentColor.opacity(0.7), count: count)
            case .item(let item):
                ItemCircleNode(item: item, size: 44, drive: session.drive)
            case .overflow(let count):
                CircleNode(label: "+\(count)", icon: nil, size: 36, color: .secondary.opacity(0.5), count: nil)
            }
        }
        .opacity(deemphasized ? 0.3 : 1.0)
        .scaleEffect(draggingNodeId == node.id ? 1.12 : 1.0)
    }
}

// MARK: - CircleNode

private struct CircleNode: View {
    let label: String
    let icon: String?
    let size: CGFloat
    let color: Color
    var count: Int? = nil

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: size, height: size)
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: size * 0.38))
                        .foregroundStyle(.white)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.85)))
                        .offset(x: 6, y: -4)
                }
            }
            Text(label)
                .font(.caption2)
                .lineLimit(1)
                .frame(maxWidth: max(size, 72))
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - ItemCircleNode

private struct ItemCircleNode: View {
    let item: Item
    let size: CGFloat
    let drive: DriveService

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: size, height: size)
                if let photoId = item.photoIds.first {
                    DriveImageView(drive: drive, fileId: photoId, contentMode: .fill)
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: size * 0.38))
                        .foregroundStyle(.secondary)
                }
            }
            .overlay(Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 1))
            Text(item.name)
                .font(.caption2)
                .lineLimit(1)
                .frame(maxWidth: max(size, 72))
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - Cursor modifier

private extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}

// MARK: - Scroll capture (trackpad two-finger scroll → pan)

private struct ScrollCapture: NSViewRepresentable {
    let onScroll: (CGSize) -> Void

    func makeNSView(context: Context) -> ScrollCaptureNSView {
        ScrollCaptureNSView(onScroll: onScroll)
    }

    func updateNSView(_ nsView: ScrollCaptureNSView, context: Context) {
        nsView.onScroll = onScroll
    }
}

private class ScrollCaptureNSView: NSView {
    var onScroll: (CGSize) -> Void

    init(onScroll: @escaping (CGSize) -> Void) {
        self.onScroll = onScroll
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func scrollWheel(with event: NSEvent) {
        onScroll(CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY))
    }
}
