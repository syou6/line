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
    var updatedAt: Date

    init(id: UUID = UUID(), title: String, body: String, tags: [String] = [], updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.body = body
        self.tags = tags
        self.updatedAt = updatedAt
    }

    // tags は後から追加したフィールドのため、旧データ（キー無し）でも読めるようにする。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        body = try c.decode(String.self, forKey: .body)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }
}

/// ファイルに書き出す前の保管庫全体の中身。
struct PersistedVault: Codable {
    var items: [VaultItem]
}
