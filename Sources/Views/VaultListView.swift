import SwiftUI

struct VaultListView: View {
    @EnvironmentObject private var state: AppState
    @State private var editing: VaultItem?
    @State private var showingNew = false
    @State private var query = ""
    @State private var selectedTag: String?

    private var allTags: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for item in state.items {
            for tag in item.tags where !seen.contains(tag) {
                seen.insert(tag)
                ordered.append(tag)
            }
        }
        return ordered.sorted()
    }

    private var filtered: [VaultItem] {
        state.items.filter { item in
            let matchesTag = selectedTag == nil || item.tags.contains(selectedTag!)
            let q = query.trimmingCharacters(in: .whitespaces)
            let matchesQuery = q.isEmpty
                || item.title.localizedCaseInsensitiveContains(q)
                || item.body.localizedCaseInsensitiveContains(q)
                || item.tags.contains { $0.localizedCaseInsensitiveContains(q) }
            return matchesTag && matchesQuery
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BrandBackground()
                if state.items.isEmpty {
                    emptyState
                } else {
                    listContent
                }
            }
            .navigationTitle("メモ")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if state.isDecoySession { decoyBadge }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingNew = true } label: {
                        Image(systemName: "plus")
                            .font(.headline)
                    }
                }
            }
            .sheet(item: $editing) { item in ItemEditView(item: item) }
            .sheet(isPresented: $showingNew) { ItemEditView(item: nil) }
        }
    }

    private var listContent: some View {
        List {
            if !allTags.isEmpty {
                tagFilterBar
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            ForEach(filtered) { item in
                Button { editing = item } label: { row(for: item) }
                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .onDelete(perform: deleteFiltered)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .searchable(text: $query, prompt: "メモを検索")
    }

    private func row(for item: VaultItem) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Theme.accentGradient)
                .frame(width: 4)
                .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 5) {
                Text(item.title.isEmpty ? "（無題）" : item.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                if !item.body.isEmpty {
                    Text(item.body)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(2)
                }
                if !item.tags.isEmpty {
                    TagChipsView(tags: item.tags)
                }
            }
            Spacer(minLength: 0)
        }
        .card()
    }

    private var decoyBadge: some View {
        Label("おとり", systemImage: "eye.slash.fill")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.orange.opacity(0.18), in: Capsule())
            .foregroundStyle(.orange)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.doc.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.accentSoft)
            Text("メモがありません")
                .font(.headline)
                .foregroundStyle(.white)
            Text("右上の＋から暗号化メモを追加できます。")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    private var tagFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(title: "すべて", active: selectedTag == nil) { selectedTag = nil }
                ForEach(allTags, id: \.self) { tag in
                    filterChip(title: tag, active: selectedTag == tag) {
                        selectedTag = (selectedTag == tag) ? nil : tag
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func filterChip(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(active ? .semibold : .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    active ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.white.opacity(0.08)),
                    in: Capsule()
                )
                .foregroundStyle(active ? Color.white : Color.white.opacity(0.75))
        }
        .buttonStyle(.plain)
    }

    private func deleteFiltered(at offsets: IndexSet) {
        let ids = offsets.map { filtered[$0].id }
        let originalOffsets = IndexSet(state.items.enumerated()
            .filter { ids.contains($0.element.id) }
            .map { $0.offset })
        state.delete(at: originalOffsets)
    }
}
