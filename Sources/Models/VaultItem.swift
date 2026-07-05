import Foundation

/// 保管庫の種別。
/// - primary: 本来のプライベート保管庫。
/// - decoy:   別PINで開く「おとり」保管庫。強要された場合など、
///            本来の保管庫を出さずに済ませるための正規のセキュリティ機能。
enum VaultKind: String, CaseIterable, Codable {
    case primary
    case decoy
}

/// 暗号化して保存する1件のメモ。
struct VaultItem: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var body: String
    var tags: [String]
    var folder: String?
    var isPinned: Bool
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        body: String,
        tags: [String] = [],
        folder: String? = nil,
        isPinned: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.tags = tags
        self.folder = folder
        self.isPinned = isPinned
        self.updatedAt = updatedAt
    }

    // tags / folder / isPinned は後から追加したフィールドのため、
    // 旧データ（キー無し）でも読めるようにする。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        body = try c.decode(String.self, forKey: .body)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        folder = try c.decodeIfPresent(String.self, forKey: .folder)
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
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
