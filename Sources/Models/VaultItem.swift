import Foundation

/// 保管庫の種別。
/// - primary: 本来のプライベート保管庫。
/// - decoy:   別PINで開く「おとり」保管庫。強要された場合など、
///            本来の保管庫を出さずに済ませるための正規のセキュリティ機能。
enum VaultKind: String, CaseIterable, Codable {
    case primary
    case decoy
}

/// チェックリストの1項目。
struct ChecklistItem: Identifiable, Codable, Equatable {
    var id: UUID
    var text: String
    var isDone: Bool

    init(id: UUID = UUID(), text: String, isDone: Bool = false) {
        self.id = id
        self.text = text
        self.isDone = isDone
    }
}

/// 画像添付。JPEGバイト列をメモ本体と一緒に暗号化保存する。
struct Attachment: Identifiable, Codable, Equatable {
    var id: UUID
    var data: Data
    var createdAt: Date

    init(id: UUID = UUID(), data: Data, createdAt: Date = Date()) {
        self.id = id
        self.data = data
        self.createdAt = createdAt
    }
}

/// 暗号化して保存する1件のメモ。
struct VaultItem: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var body: String
    var tags: [String]
    var folder: String?
    var isPinned: Bool
    var checklist: [ChecklistItem]
    var attachments: [Attachment]
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        body: String,
        tags: [String] = [],
        folder: String? = nil,
        isPinned: Bool = false,
        checklist: [ChecklistItem] = [],
        attachments: [Attachment] = [],
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.tags = tags
        self.folder = folder
        self.isPinned = isPinned
        self.checklist = checklist
        self.attachments = attachments
        self.updatedAt = updatedAt
    }

    // 後から追加したフィールドは、旧データ（キー無し）でも読めるようにする。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        body = try c.decode(String.self, forKey: .body)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        folder = try c.decodeIfPresent(String.self, forKey: .folder)
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        checklist = try c.decodeIfPresent([ChecklistItem].self, forKey: .checklist) ?? []
        attachments = try c.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }

    /// チェックリストの進捗（完了数, 総数）。
    var checklistProgress: (done: Int, total: Int) {
        (checklist.filter(\.isDone).count, checklist.count)
    }
}

/// 削除の記録（トゥームストーン）。同期時に「削除がリモートで復活する」のを防ぐ。
struct Tombstone: Codable, Equatable {
    var id: UUID
    var deletedAt: Date
}

/// ファイルに書き出す前の保管庫全体の中身。
struct PersistedVault: Codable {
    var items: [VaultItem]
    var tombstones: [Tombstone]

    init(items: [VaultItem], tombstones: [Tombstone] = []) {
        self.items = items
        self.tombstones = tombstones
    }

    // tombstones は後から追加したフィールドのため、旧blobでも読めるようにする。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decode([VaultItem].self, forKey: .items)
        tombstones = try c.decodeIfPresent([Tombstone].self, forKey: .tombstones) ?? []
    }
}
