import Foundation

/// 共有拡張から受け取った1件の下書き。
/// 共有拡張はPIN鍵を持てないため、いったんこの中間形式で受け取り、
/// 本体アプリが解錠時に取り込んで本来の暗号化保管庫へマージする。
struct InboxDraft: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var body: String
    var createdAt: Date

    init(id: UUID = UUID(), title: String, body: String, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.body = body
        self.createdAt = createdAt
    }

    /// 保管庫のメモへ変換する。共有由来と分かるようタグを付ける。
    func toVaultItem() -> VaultItem {
        VaultItem(title: title, body: body, tags: ["共有"], updatedAt: createdAt)
    }
}

/// 下書き1件のJSONエンコード／デコード（純粋・テスト可能）。
enum InboxCodec {
    static func encode(_ draft: InboxDraft) throws -> Data {
        try JSONEncoder().encode(draft)
    }

    static func decode(_ data: Data) throws -> InboxDraft {
        try JSONDecoder().decode(InboxDraft.self, from: data)
    }

    /// 共有テキスト（本文 or URL）から下書きを組み立てる。
    /// 先頭行をタイトル、全体を本文にする。
    static func makeDraft(from text: String, now: Date) -> InboxDraft {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = trimmed.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? trimmed
        let title = String(firstLine.prefix(40))
        return InboxDraft(title: title, body: trimmed, createdAt: now)
    }
}
