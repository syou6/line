import SwiftUI

/// メモの新規作成 / 編集シート。item==nil で新規。
struct ItemEditView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    private let original: VaultItem?
    @State private var title: String
    @State private var bodyText: String
    @State private var tagText: String
    @State private var folderText: String
    @State private var isPinned: Bool

    init(item: VaultItem?) {
        self.original = item
        _title = State(initialValue: item?.title ?? "")
        _bodyText = State(initialValue: item?.body ?? "")
        _tagText = State(initialValue: (item?.tags ?? []).joined(separator: ", "))
        _folderText = State(initialValue: item?.folder ?? "")
        _isPinned = State(initialValue: item?.isPinned ?? false)
    }

    private var parsedFolder: String? {
        let f = folderText.trimmingCharacters(in: .whitespaces)
        return f.isEmpty ? nil : f
    }

    private var parsedTags: [String] {
        tagText
            .split(whereSeparator: { $0 == "," || $0 == "、" || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BrandBackground()
                form
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
                            body: bodyText,
                            tags: parsedTags,
                            folder: parsedFolder,
                            isPinned: isPinned
                        )
                        state.upsert(item)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(title.isEmpty && bodyText.isEmpty)
                }
            }
        }
    }

    private var form: some View {
        Form {
            Section("タイトル") {
                TextField("タイトル", text: $title)
            }
            Section("本文") {
                TextEditor(text: $bodyText)
                    .frame(minHeight: 200)
            }
            Section {
                TextField("例: 仕事, アイデア, 買い物", text: $tagText)
                    .autocorrectionDisabled()
                if !parsedTags.isEmpty {
                    TagChipsView(tags: parsedTags)
                }
            } header: {
                Text("タグ")
            } footer: {
                Text("カンマ区切りで複数指定できます。")
            }
            Section("整理") {
                TextField("フォルダ（例: 仕事）", text: $folderText)
                    .autocorrectionDisabled()
                Toggle(isOn: $isPinned) {
                    Label("ピン留め", systemImage: "pin")
                }
            }
        }
        .scrollContentBackground(.hidden)
    }
}
