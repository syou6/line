import SwiftUI
import PhotosUI
import UIKit

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
    @State private var checklist: [ChecklistItem]
    @State private var attachments: [Attachment]

    @State private var newCheckText = ""
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var isLoadingPhotos = false

    init(item: VaultItem?) {
        self.original = item
        _title = State(initialValue: item?.title ?? "")
        _bodyText = State(initialValue: item?.body ?? "")
        _tagText = State(initialValue: (item?.tags ?? []).joined(separator: ", "))
        _folderText = State(initialValue: item?.folder ?? "")
        _isPinned = State(initialValue: item?.isPinned ?? false)
        _checklist = State(initialValue: item?.checklist ?? [])
        _attachments = State(initialValue: item?.attachments ?? [])
    }

    private var parsedTags: [String] {
        tagText
            .split(whereSeparator: { $0 == "," || $0 == "、" || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var parsedFolder: String? {
        let f = folderText.trimmingCharacters(in: .whitespaces)
        return f.isEmpty ? nil : f
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
                    Button("保存", action: save)
                        .fontWeight(.semibold)
                        .disabled(isEmpty)
                }
            }
            .onChange(of: photoItems) { _ in loadPhotos() }
        }
    }

    private var isEmpty: Bool {
        title.isEmpty && bodyText.isEmpty && checklist.isEmpty && attachments.isEmpty
    }

    private func save() {
        let item = VaultItem(
            id: original?.id ?? UUID(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            body: bodyText,
            tags: parsedTags,
            folder: parsedFolder,
            isPinned: isPinned,
            checklist: checklist.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty },
            attachments: attachments
        )
        state.upsert(item)
        dismiss()
    }

    private var form: some View {
        Form {
            Section("タイトル") {
                TextField("タイトル", text: $title)
            }
            Section("本文") {
                TextEditor(text: $bodyText)
                    .frame(minHeight: 160)
            }
            checklistSection
            attachmentsSection
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

    // MARK: - チェックリスト

    private var checklistSection: some View {
        Section {
            ForEach($checklist) { $entry in
                HStack(spacing: 10) {
                    Button {
                        entry.isDone.toggle()
                    } label: {
                        Image(systemName: entry.isDone ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(entry.isDone ? Theme.accent : .secondary)
                    }
                    .buttonStyle(.plain)
                    TextField("項目", text: $entry.text)
                        .strikethrough(entry.isDone)
                        .foregroundStyle(entry.isDone ? .secondary : .primary)
                }
            }
            .onDelete { checklist.remove(atOffsets: $0) }

            HStack(spacing: 10) {
                Image(systemName: "plus.circle").foregroundStyle(Theme.accent)
                TextField("項目を追加", text: $newCheckText)
                    .onSubmit(addCheckItem)
                if !newCheckText.isEmpty {
                    Button("追加", action: addCheckItem)
                }
            }
        } header: {
            HStack {
                Text("チェックリスト")
                Spacer()
                if !checklist.isEmpty {
                    let p = VaultItem(title: "", body: "", checklist: checklist).checklistProgress
                    Text("\(p.done)/\(p.total)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func addCheckItem() {
        let text = newCheckText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        checklist.append(ChecklistItem(text: text))
        newCheckText = ""
    }

    // MARK: - 添付画像

    private var attachmentsSection: some View {
        Section {
            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(attachments) { att in
                            attachmentThumb(att)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            PhotosPicker(selection: $photoItems, maxSelectionCount: 5, matching: .images) {
                Label(isLoadingPhotos ? "読み込み中…" : "写真を追加", systemImage: "photo.badge.plus")
            }
            .disabled(isLoadingPhotos)
        } header: {
            Text("添付")
        } footer: {
            Text("画像は縮小してメモと一緒に暗号化保存されます。")
        }
    }

    private func attachmentThumb(_ att: Attachment) -> some View {
        ZStack(alignment: .topTrailing) {
            if let ui = UIImage(data: att.data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            Button {
                attachments.removeAll { $0.id == att.id }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white, .black.opacity(0.6))
                    .padding(4)
            }
        }
    }

    private func loadPhotos() {
        guard !photoItems.isEmpty else { return }
        isLoadingPhotos = true
        let items = photoItems
        Task {
            var loaded: [Attachment] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let jpeg = ImageProcessing.makeJPEG(from: data) {
                    loaded.append(Attachment(data: jpeg))
                }
            }
            await MainActor.run {
                attachments.append(contentsOf: loaded)
                photoItems = []
                isLoadingPhotos = false
            }
        }
    }
}
