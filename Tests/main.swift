import Foundation

// 本物の Sources/Models/VaultItem.swift と Sources/Storage/VaultMerge.swift を
// 一緒にコンパイルして、実装そのものを検証するテスト。

var passed = 0
var failed = 0

func expect(_ cond: Bool, _ name: String) {
    if cond { passed += 1; print("  ✅ \(name)") }
    else { failed += 1; print("  ❌ \(name)") }
}

let base = Date(timeIntervalSince1970: 1_700_000_000)
func at(_ minutes: Double) -> Date { base.addingTimeInterval(minutes * 60) }

func item(_ id: UUID, _ title: String, updated: Double, pinned: Bool = false) -> VaultItem {
    VaultItem(id: id, title: title, body: "b", isPinned: pinned, updatedAt: at(updated))
}

// MARK: - 1. 基本の削除伝播

print("1. 削除がリモートの古いblobから復活しない")
do {
    let id = UUID()
    // ローカル: 削除済み(墓標のみ) / リモート: まだ持っている(古い)
    let local = PersistedVault(items: [], tombstones: [Tombstone(id: id, deletedAt: at(10))])
    let remote = PersistedVault(items: [item(id, "note", updated: 5)])
    let merged = VaultMerge.merge(local: local, remote: remote)
    expect(merged.items.isEmpty, "削除が勝つ(itemは復活しない)")
    expect(merged.tombstones.count == 1 && merged.tombstones[0].id == id, "墓標は保持される")
}

print("2. 削除後に別端末で編集された場合は編集が勝つ")
do {
    let id = UUID()
    let local = PersistedVault(items: [], tombstones: [Tombstone(id: id, deletedAt: at(10))])
    let remote = PersistedVault(items: [item(id, "edited later", updated: 20)])
    let merged = VaultMerge.merge(local: local, remote: remote)
    expect(merged.items.count == 1 && merged.items[0].title == "edited later", "新しい編集が勝つ")
    expect(merged.tombstones.isEmpty, "負けた墓標は破棄される")
}

print("3. last-writer-wins")
do {
    let id = UUID()
    let local = PersistedVault(items: [item(id, "old", updated: 5)])
    let remote = PersistedVault(items: [item(id, "new", updated: 9)])
    let merged = VaultMerge.merge(local: local, remote: remote)
    expect(merged.items.count == 1 && merged.items[0].title == "new", "リモートの新しい方を採用")
    let merged2 = VaultMerge.merge(local: remote, remote: local)
    expect(merged2.items.count == 1 && merged2.items[0].title == "new", "向きを逆にしても同じ結果(対称性)")
}

print("4. 双方の独自メモは両方残る")
do {
    let a = UUID(), b = UUID()
    let local = PersistedVault(items: [item(a, "local only", updated: 1)])
    let remote = PersistedVault(items: [item(b, "remote only", updated: 2)])
    let merged = VaultMerge.merge(local: local, remote: remote)
    expect(merged.items.count == 2, "和集合になる")
}

print("5. 同一IDの墓標は新しいdeletedAtを採用")
do {
    let id = UUID()
    let local = PersistedVault(items: [], tombstones: [Tombstone(id: id, deletedAt: at(5))])
    let remote = PersistedVault(items: [], tombstones: [Tombstone(id: id, deletedAt: at(8))])
    let merged = VaultMerge.merge(local: local, remote: remote)
    expect(merged.tombstones.count == 1 && merged.tombstones[0].deletedAt == at(8), "max(deletedAt)")
}

print("6. deletedAt == updatedAt の境界は削除が勝つ")
do {
    let id = UUID()
    let local = PersistedVault(items: [], tombstones: [Tombstone(id: id, deletedAt: at(7))])
    let remote = PersistedVault(items: [item(id, "same instant", updated: 7)])
    let merged = VaultMerge.merge(local: local, remote: remote)
    expect(merged.items.isEmpty, ">= なので削除優先")
}

print("7. 収束性: 一度マージした結果同士を再マージしても変わらない(冪等)")
do {
    let a = UUID(), b = UUID(), c = UUID()
    let local = PersistedVault(
        items: [item(a, "A", updated: 3), item(b, "B", updated: 4)],
        tombstones: [Tombstone(id: c, deletedAt: at(9))]
    )
    let remote = PersistedVault(
        items: [item(b, "B2", updated: 6), item(c, "C", updated: 5)],
        tombstones: [Tombstone(id: a, deletedAt: at(1))]
    )
    let m1 = VaultMerge.merge(local: local, remote: remote)
    let m2 = VaultMerge.merge(local: m1, remote: m1)
    expect(Set(m1.items.map(\.id)) == Set(m2.items.map(\.id)), "items が収束")
    expect(Set(m1.tombstones.map(\.id)) == Set(m2.tombstones.map(\.id)), "tombstones が収束")
    // 期待値も確認: aは編集(3)>墓標(1)で生存、bはB2、cは墓標(9)>編集(5)で削除
    expect(m1.items.contains { $0.id == a }, "a: 編集が墓標より新しいので生存")
    expect(m1.items.first { $0.id == b }?.title == "B2", "b: LWW")
    expect(!m1.items.contains { $0.id == c }, "c: 削除が勝つ")
}

// MARK: - 後方互換デコード

print("8. 旧形式JSON(tags/folder/isPinned/tombstones無し)が読める")
do {
    let legacy = """
    {"items":[{"id":"\(UUID().uuidString)","title":"old note","body":"hello","updatedAt":700000000}]}
    """
    let decoder = JSONDecoder()
    // アプリはデフォルトの Date エンコード(secondsSinceReferenceDate)を使用
    let vault = try? decoder.decode(PersistedVault.self, from: Data(legacy.utf8))
    expect(vault != nil, "デコード成功")
    expect(vault?.items.first?.tags == [], "tags は空配列にフォールバック")
    expect(vault?.items.first?.folder == nil, "folder は nil")
    expect(vault?.items.first?.isPinned == false, "isPinned は false")
    expect(vault?.tombstones.isEmpty == true, "tombstones は空")
}

print("9. 現行形式のエンコード→デコードのラウンドトリップ")
do {
    let v = PersistedVault(
        items: [VaultItem(title: "t", body: "b", tags: ["x"], folder: "f", isPinned: true)],
        tombstones: [Tombstone(id: UUID(), deletedAt: Date())]
    )
    let data = try! JSONEncoder().encode(v)
    let back = try? JSONDecoder().decode(PersistedVault.self, from: data)
    expect(back != nil, "ラウンドトリップ成功")
    expect(back?.items.first?.folder == "f" && back?.items.first?.isPinned == true, "全フィールド保持")
    expect(back?.tombstones.count == 1, "墓標も保持")
}

// MARK: - ロックアウト方針

print("10. ロックアウトのバックオフ")
do {
    let p = LockoutPolicy(freeAttempts: 5)
    expect(p.lockoutDuration(failedAttempts: 5) == 0, "5回までは遅延なし")
    expect(p.lockoutDuration(failedAttempts: 6) == 30, "6回目=30秒")
    expect(p.lockoutDuration(failedAttempts: 7) == 60, "7回目=60秒")
    expect(p.lockoutDuration(failedAttempts: 8) == 120, "8回目=120秒")
    expect(p.lockoutDuration(failedAttempts: 30) == 3600, "上限は3600秒で頭打ち")
}

print("11. 自動消去しきい値")
do {
    let off = LockoutPolicy(autoWipeAttempts: nil)
    expect(!off.shouldWipe(failedAttempts: 100), "nilなら消去しない")
    let on = LockoutPolicy(autoWipeAttempts: 10)
    expect(!on.shouldWipe(failedAttempts: 9), "9回では消去しない")
    expect(on.shouldWipe(failedAttempts: 10), "10回で消去")
}

print("12. 残りロックアウト時間の計算")
do {
    let p = LockoutPolicy(freeAttempts: 5)
    var st = AttemptState(failed: 6, lastFailure: at(0)) // 30秒ロック
    expect(st.isLockedOut(policy: p, now: at(0)), "直後はロック中")
    expect(st.remainingLockout(policy: p, now: base.addingTimeInterval(10)) == 20, "10秒後は残り20秒")
    expect(!st.isLockedOut(policy: p, now: base.addingTimeInterval(30)), "30秒後は解除")
    st.failed = 3
    expect(!st.isLockedOut(policy: p, now: at(0)), "free以内はロックされない")
}

// MARK: - 自動ロック猶予

print("13. 自動ロックの猶予判定")
do {
    expect(AutoLock.shouldLock(backgroundedAt: at(0), now: at(0), grace: .immediate), "即時は常にロック")
    expect(!AutoLock.shouldLock(backgroundedAt: at(0), now: base.addingTimeInterval(30), grace: .oneMinute),
           "1分猶予・30秒後はロックしない")
    expect(AutoLock.shouldLock(backgroundedAt: at(0), now: base.addingTimeInterval(60), grace: .oneMinute),
           "1分猶予・60秒後はロック")
    expect(!AutoLock.shouldLock(backgroundedAt: nil, now: at(0), grace: .fiveMinutes),
           "背景時刻不明なら猶予ありではロックしない")
}

// MARK: - バックアップ ヘッダ検証

print("14. バックアップのヘッダ検証")
do {
    let ok = BackupEnvelope(format: "PrivacyVaultBackup", version: 1, salt: Data([1]), ciphertext: Data([2]))
    var threw = false
    do { try BackupFormat.validateHeader(ok) } catch { threw = true }
    expect(!threw, "正しいヘッダは通る")

    let badFormat = BackupEnvelope(format: "Other", version: 1, salt: Data(), ciphertext: Data())
    var e1: BackupError?
    do { try BackupFormat.validateHeader(badFormat) } catch { e1 = error as? BackupError }
    expect(e1 == .wrongFormat, "形式違いは wrongFormat")

    let future = BackupEnvelope(format: "PrivacyVaultBackup", version: 99, salt: Data(), ciphertext: Data())
    var e2: BackupError?
    do { try BackupFormat.validateHeader(future) } catch { e2 = error as? BackupError }
    expect(e2 == .unsupportedVersion, "新バージョンは unsupportedVersion")
}

print("15. BackupEnvelopeのJSONラウンドトリップ(Dataはbase64)")
do {
    let env = BackupEnvelope(format: "PrivacyVaultBackup", version: 1,
                             salt: Data([0,1,2,3]), ciphertext: Data([9,8,7]))
    let data = try! JSONEncoder().encode(env)
    let json = String(data: data, encoding: .utf8) ?? ""
    expect(json.contains("\"salt\""), "saltフィールドが存在")
    let back = try? JSONDecoder().decode(BackupEnvelope.self, from: data)
    expect(back == env, "ラウンドトリップで一致")
}

// MARK: - リッチメモ（チェックリスト・添付）

print("16. checklist/attachments 無しの旧JSONが読める")
do {
    let legacy = """
    {"items":[{"id":"\(UUID().uuidString)","title":"t","body":"b","tags":["x"],"isPinned":true,"updatedAt":700000000}]}
    """
    let v = try? JSONDecoder().decode(PersistedVault.self, from: Data(legacy.utf8))
    expect(v != nil, "デコード成功")
    expect(v?.items.first?.checklist.isEmpty == true, "checklist は空配列にフォールバック")
    expect(v?.items.first?.attachments.isEmpty == true, "attachments は空配列にフォールバック")
    expect(v?.items.first?.isPinned == true, "既存フィールドは維持")
}

print("17. チェックリスト進捗の計算")
do {
    let it = VaultItem(title: "t", body: "", checklist: [
        ChecklistItem(text: "a", isDone: true),
        ChecklistItem(text: "b", isDone: false),
        ChecklistItem(text: "c", isDone: true),
    ])
    expect(it.checklistProgress.done == 2 && it.checklistProgress.total == 3, "2/3")
    let empty = VaultItem(title: "t", body: "")
    expect(empty.checklistProgress.total == 0, "空は 0/0")
}

print("18. checklist/attachmentsを含むラウンドトリップ")
do {
    let att = Attachment(data: Data([0xFF, 0xD8, 0xFF]))  // JPEGヘッダ風のダミー
    let it = VaultItem(title: "t", body: "b",
                       checklist: [ChecklistItem(text: "task", isDone: true)],
                       attachments: [att])
    let v = PersistedVault(items: [it])
    let data = try! JSONEncoder().encode(v)
    let back = try? JSONDecoder().decode(PersistedVault.self, from: data)
    expect(back?.items.first?.checklist.first?.isDone == true, "checklist保持")
    expect(back?.items.first?.attachments.first?.data == Data([0xFF, 0xD8, 0xFF]), "attachmentバイト保持(base64)")
}

print("19. リッチメモがマージを壊さない(LWWで新しい方が全フィールド勝つ)")
do {
    let id = UUID()
    let old = VaultItem(id: id, title: "old", body: "", updatedAt: at(1))
    let new = VaultItem(id: id, title: "new", body: "",
                        checklist: [ChecklistItem(text: "x")],
                        attachments: [Attachment(data: Data([1]))],
                        updatedAt: at(2))
    let merged = VaultMerge.merge(
        local: PersistedVault(items: [old]),
        remote: PersistedVault(items: [new]))
    expect(merged.items.count == 1, "1件に統合")
    expect(merged.items.first?.checklist.count == 1 && merged.items.first?.attachments.count == 1,
           "新しい方のリッチ内容が採用される")
}

// MARK: - 共有受信箱

print("20. 共有テキストから下書きを組み立てる")
do {
    let d = InboxCodec.makeDraft(from: "  買い物メモ\n牛乳とパン  ", now: at(0))
    expect(d.title == "買い物メモ", "先頭行がタイトル")
    expect(d.body == "買い物メモ\n牛乳とパン", "全体が本文(トリム済み)")
    let long = InboxCodec.makeDraft(from: String(repeating: "あ", count: 100), now: at(0))
    expect(long.title.count == 40, "タイトルは40字で切り詰め")
}

print("21. 下書きのJSONラウンドトリップと変換")
do {
    let d = InboxDraft(title: "t", body: "b", createdAt: at(3))
    let data = try! InboxCodec.encode(d)
    let back = try? InboxCodec.decode(data)
    expect(back == d, "ラウンドトリップで一致")
    let item = d.toVaultItem()
    expect(item.title == "t" && item.body == "b", "VaultItemへ変換")
    expect(item.tags == ["共有"], "共有タグが付く")
    expect(item.updatedAt == at(3), "作成時刻を引き継ぐ")
}

print("")
print("結果: \(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
