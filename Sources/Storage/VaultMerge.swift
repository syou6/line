import Foundation

/// 同期マージの純粋ロジック。UIに依存しないためテスト可能。
enum VaultMerge {
    /// マージ規則:
    /// 1. トゥームストーンは両側の和集合(同一IDは新しい deletedAt を採用)。
    /// 2. itemは last-writer-wins(updatedAt が新しい方)。
    /// 3. トゥームストーンの deletedAt >= item の updatedAt なら削除が勝つ。
    ///    itemの方が新しい(削除後に別端末で編集された)場合はitemが勝ち、トゥームストーンを破棄。
    static func merge(local: PersistedVault, remote: PersistedVault) -> PersistedVault {
        var deadAt: [UUID: Date] = [:]
        for t in local.tombstones + remote.tombstones {
            if let existing = deadAt[t.id] {
                deadAt[t.id] = max(existing, t.deletedAt)
            } else {
                deadAt[t.id] = t.deletedAt
            }
        }

        var byID: [UUID: VaultItem] = [:]
        for item in local.items { byID[item.id] = item }
        for item in remote.items {
            if let existing = byID[item.id] {
                if item.updatedAt > existing.updatedAt { byID[item.id] = item }
            } else {
                byID[item.id] = item
            }
        }

        var survivors: [VaultItem] = []
        for item in byID.values {
            if let died = deadAt[item.id], died >= item.updatedAt {
                continue // 削除が勝ち
            }
            deadAt.removeValue(forKey: item.id) // itemが勝ったので墓標を破棄
            survivors.append(item)
        }

        let mergedTombstones = deadAt.map { Tombstone(id: $0.key, deletedAt: $0.value) }
        return PersistedVault(items: survivors, tombstones: mergedTombstones)
    }
}
