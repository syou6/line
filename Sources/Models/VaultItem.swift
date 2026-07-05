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
    var updatedAt: Date

    init(id: UUID = UUID(), title: String, body: String, updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.body = body
        self.updatedAt = updatedAt
    }
}

/// ファイルに書き出す前の保管庫全体の中身。
struct PersistedVault: Codable {
    var items: [VaultItem]
}
