import SwiftUI

/// メモの新規作成 / 編集シート。item==nil で新規。
struct ItemEditView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    private let original: VaultItem?
    @State private var title: String
    @State private var bodyText: String

    init(item: VaultItem?) {
        self.original = item
        _title = State(initialValue: item?.title ?? "")
        _bodyText = State(initialValue: item?.body ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("タイトル") {
                    TextField("タイトル", text: $title)
                }
                Section("本文") {
                    TextEditor(text: $bodyText)
                        .frame(minHeight: 220)
                }
            }
            .navigationTitle(original == nil ? "新規メモ" : "メモを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let item = VaultItem(
                            id: original?.id ?? UUID(),
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            body: bodyText
                        )
                        state.upsert(item)
                        dismiss()
                    }
                    .disabled(title.isEmpty && bodyText.isEmpty)
                }
            }
        }
    }
}
