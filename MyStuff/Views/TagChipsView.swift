import SwiftUI

/// Flow layout for chips that wraps to new lines.
/// Uses SwiftUI's `Layout` protocol (iOS 16+ / macOS 13+).
struct TagChipsWrapLayout: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // When width is unspecified, assume a reasonable content width so height
        // accounts for wrapping instead of a single long row.
        let maxWidth = proposal.width ?? 400
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return CGSize(width: min(maxWidth, max(x - spacing, 0)), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = proposal.width ?? 400
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.minX + maxWidth {
                x = bounds.minX
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(width: size.width, height: size.height))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}

struct TagChip: View {
    let text: String
    var isEditable: Bool = false
    var onTap: (() -> Void)? = nil
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
            if let onRemove {
                Button(role: .destructive) { onRemove() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove tag \(text)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary)
        .clipShape(Capsule())
        .overlay {
            if isEditable {
                Capsule()
                    .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
            }
        }
        .contentShape(Capsule())
        .onTapGesture { onTap?() }
        .accessibilityAddTraits(isEditable ? .isButton : [])
    }
}

/// Read-only chips (no x, no editing).
struct TagChipsView: View {
    let tags: [String]

    var body: some View {
        TagChipsWrapLayout(spacing: 8, rowSpacing: 8) {
            ForEach(tags, id: \.self) { tag in
                TagChip(text: tag)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Editable chips used in ItemFormView. Persists changes through the binding (save still happens in the form).
struct TagChipsEditor: View {
    @Binding var tags: [String]
    @State private var newTagText: String = ""
    @State private var editingIndex: Int? = nil
    @State private var editingText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TagChipsWrapLayout(spacing: 8, rowSpacing: 8) {
                ForEach(Array(tags.enumerated()), id: \.offset) { index, tag in
                    if editingIndex == index {
                        TextField("Tag", text: $editingText)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 90)
                            .onSubmit { commitEdit() }
                    } else {
                        TagChip(
                            text: tag,
                            isEditable: true,
                            onTap: { beginEdit(index: index) },
                            onRemove: { remove(at: index) }
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                TextField("Add tag…", text: $newTagText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitNewTags() }
                Button("Add") { commitNewTags() }
                    .disabled(newTagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onChange(of: tags) { _, _ in
            if let idx = editingIndex, idx >= tags.count {
                editingIndex = nil
                editingText = ""
            }
        }
    }

    private func beginEdit(index: Int) {
        editingIndex = index
        editingText = tags[index]
    }

    private func commitEdit() {
        guard let idx = editingIndex else { return }
        let updated = normalizeTags([editingText])
        if updated.isEmpty {
            remove(at: idx)
        } else {
            tags[idx] = updated[0]
            tags = normalizeTags(tags)
        }
        editingIndex = nil
        editingText = ""
    }

    private func commitNewTags() {
        let parts = newTagText
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        let normalized = normalizeTags(parts)
        guard !normalized.isEmpty else { return }
        tags = normalizeTags(tags + normalized)
        newTagText = ""
    }

    private func remove(at index: Int) {
        guard tags.indices.contains(index) else { return }
        tags.remove(at: index)
        tags = normalizeTags(tags)
        if editingIndex == index {
            editingIndex = nil
            editingText = ""
        }
    }

    private func normalizeTags(_ input: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in input {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            let key = t.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(t)
        }
        return out
    }
}

