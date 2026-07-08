import SwiftUI

/// 並び順の選択肢。
enum NoteSortOrder: String, CaseIterable, Identifiable {
    case updated = "更新が新しい順"
    case title = "タイトル順"
    var id: String { rawValue }
}

struct VaultListView: View {
    @EnvironmentObject private var state: AppState
    @State private var editing: VaultItem?
    @State private var showingNew = false
    @State private var query = ""
    @State private var selectedTag: String?
    @State private var selectedFolder: String?
    @State private var sortOrder: NoteSortOrder = .updated

    // MARK: - 派生データ

    private var allTags: [String] {
        Array(Set(state.items.flatMap(\.tags))).sorted()
    }

    private var allFolders: [String] {
        Array(Set(state.items.compactMap(\.folder))).sorted()
    }

    private var filtered: [VaultItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        var result = state.items.filter { item in
            let matchesTag = selectedTag == nil || item.tags.contains(selectedTag!)
            let matchesFolder = selectedFolder == nil || item.folder == selectedFolder
            let matchesQuery = q.isEmpty
                || item.title.localizedCaseInsensitiveContains(q)
                || item.body.localizedCaseInsensitiveContains(q)
                || item.tags.contains { $0.localizedCaseInsensitiveContains(q) }
                || (item.folder?.localizedCaseInsensitiveContains(q) ?? false)
            return matchesTag && matchesFolder && matchesQuery
        }
        switch sortOrder {
        case .updated:
            result.sort { $0.updatedAt > $1.updatedAt }
        case .title:
            result.sort { $0.title.localizedCompare($1.title) == .orderedAscending }
        }
        return result
    }

    private var pinned: [VaultItem] { filtered.filter(\.isPinned) }
    private var unpinned: [VaultItem] { filtered.filter { !$0.isPinned } }

    // MARK: - Body

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
            .navigationTitle(selectedFolder ?? "メモ")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if state.isDecoySession { decoyBadge }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    filterMenu
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
            if !pinned.isEmpty {
                Section {
                    ForEach(pinned) { item in itemRow(item) }
                } header: {
                    sectionHeader("ピン留め", systemImage: "pin.fill")
                }
            }
            Section {
                ForEach(unpinned) { item in itemRow(item) }
            } header: {
                if !pinned.isEmpty {
                    sectionHeader("その他", systemImage: "tray")
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .searchable(text: $query, prompt: "メモを検索")
    }

    private func itemRow(_ item: VaultItem) -> some View {
        Button { editing = item } label: { row(for: item) }
            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    state.togglePin(item.id)
                } label: {
                    Label(item.isPinned ? "解除" : "ピン留め",
                          systemImage: item.isPinned ? "pin.slash" : "pin")
                }
                .tint(Theme.accent)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    state.delete(ids: [item.id])
                } label: {
                    Label("削除", systemImage: "trash")
                }
            }
    }

    private func sectionHeader(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.55))
            .textCase(nil)
    }

    private func row(for item: VaultItem) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Theme.accentGradient)
                .frame(width: 4)
                .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.accentSoft)
                    }
                    Text(item.title.isEmpty ? "（無題）" : item.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    if let folder = item.folder {
                        Text(folder)
                            .font(.caption2)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color.white.opacity(0.10), in: Capsule())
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
                if !item.body.isEmpty {
                    Text(item.body)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(2)
                }
                if !item.tags.isEmpty {
                    TagChipsView(tags: item.tags)
                }
                if item.checklist.count > 0 || item.attachments.count > 0 {
                    HStack(spacing: 12) {
                        if item.checklist.count > 0 {
                            let p = item.checklistProgress
                            Label("\(p.done)/\(p.total)", systemImage: "checklist")
                                .foregroundStyle(p.done == p.total ? Theme.accentSoft : .white.opacity(0.5))
                        }
                        if item.attachments.count > 0 {
                            Label("\(item.attachments.count)", systemImage: "paperclip")
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    .font(.caption2)
                }
            }
            Spacer(minLength: 0)
        }
        .card()
    }

    private var filterMenu: some View {
        Menu {
            Picker("並び順", selection: $sortOrder) {
                ForEach(NoteSortOrder.allCases) { order in
                    Text(LocalizedStringKey(order.rawValue)).tag(order)
                }
            }
            if !allFolders.isEmpty {
                Divider()
                Picker("フォルダ", selection: $selectedFolder) {
                    Text("すべてのフォルダ").tag(String?.none)
                    ForEach(allFolders, id: \.self) { folder in
                        Label(folder, systemImage: "folder").tag(String?.some(folder))
                    }
                }
            }
        } label: {
            Image(systemName: selectedFolder == nil
                  ? "line.3.horizontal.decrease.circle"
                  : "line.3.horizontal.decrease.circle.fill")
                .font(.headline)
        }
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
}
