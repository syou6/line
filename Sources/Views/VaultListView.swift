import SwiftUI

struct VaultListView: View {
    @EnvironmentObject private var state: AppState
    @State private var editing: VaultItem?
    @State private var showingNew = false

    var body: some View {
        NavigationStack {
            Group {
                if state.items.isEmpty {
                    ContentUnavailableCompat(
                        title: "メモがありません",
                        systemImage: "lock.doc",
                        description: "右上の＋から暗号化メモを追加できます。"
                    )
                } else {
                    List {
                        ForEach(state.items) { item in
                            Button {
                                editing = item
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title.isEmpty ? "（無題）" : item.title)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(item.body)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .onDelete { state.delete(at: $0) }
                    }
                }
            }
            .navigationTitle("メモ")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if state.isDecoySession {
                        Label("おとり", systemImage: "eye.slash")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNew = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $editing) { item in
                ItemEditView(item: item)
            }
            .sheet(isPresented: $showingNew) {
                ItemEditView(item: nil)
            }
        }
    }
}

/// iOS16でも使えるContentUnavailableView相当の簡易版。
struct ContentUnavailableCompat: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}
