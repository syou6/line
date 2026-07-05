import Foundation
import SwiftUI
import CryptoKit

@MainActor
final class AppState: ObservableObject {
    enum Phase {
        case needsSetup   // 初回: primary保管庫がまだ無い
        case locked       // PIN / 生体認証待ち
        case unlocked     // 解錠済み
    }

    @Published private(set) var phase: Phase
    @Published private(set) var activeKind: VaultKind?
    @Published private(set) var items: [VaultItem] = []
    @Published private(set) var biometricEnabled: Bool
    @Published private(set) var iCloudSyncEnabled: Bool
    @Published var errorMessage: String?

    private var key: SymmetricKey?
    private var tombstones: [Tombstone] = []

    /// トゥームストーンの保持期間。これより古いものは保存時に破棄する。
    private static let tombstoneRetention: TimeInterval = 90 * 86_400

    var biometricAvailable: Bool { BiometricKeyStore.isAvailable }
    var isDecoySession: Bool { activeKind == .decoy }
    var decoyConfigured: Bool { VaultManager.isSetup(.decoy) }

    init() {
        phase = VaultManager.isSetup(.primary) ? .locked : .needsSetup
        biometricEnabled = BiometricKeyStore.isEnabled
        iCloudSyncEnabled = CloudSyncService.isEnabled
    }

    // MARK: - 解錠 / 施錠

    func setupPrimary(pin: String) {
        do {
            try VaultManager.create(kind: .primary, pin: pin)
            unlock(pin: pin)
        } catch {
            errorMessage = "初期設定に失敗しました"
        }
    }

    func unlock(pin: String) {
        guard let (kind, key) = VaultManager.resolve(pin: pin) else {
            errorMessage = "PINが違います"
            return
        }
        activate(kind: kind, key: key)
    }

    func unlockWithBiometrics() {
        Task.detached(priority: .userInitiated) {
            let keyData = BiometricKeyStore.load(reason: "メモのロックを解除します")
            await MainActor.run {
                guard let keyData else {
                    self.errorMessage = "生体認証に失敗しました"
                    return
                }
                self.activate(kind: .primary, key: SymmetricKey(data: keyData))
            }
        }
    }

    func lock() {
        key = nil
        activeKind = nil
        items = []
        tombstones = []
        errorMessage = nil
        phase = .locked
    }

    private func activate(kind: VaultKind, key: SymmetricKey) {
        let vault = VaultManager.loadVault(kind: kind, key: key)
        self.key = key
        self.activeKind = kind
        self.items = vault.items.sorted { $0.updatedAt > $1.updatedAt }
        self.tombstones = vault.tombstones
        self.errorMessage = nil
        self.phase = .unlocked
        syncFromCloud()
    }

    /// 現在の items + tombstones をローカルに暗号化保存する。
    private func persist() {
        guard let key, let kind = activeKind else { return }
        let cutoff = Date().addingTimeInterval(-Self.tombstoneRetention)
        tombstones.removeAll { $0.deletedAt < cutoff }
        VaultManager.saveVault(PersistedVault(items: items, tombstones: tombstones), kind: kind, key: key)
    }

    // MARK: - iCloud 同期

    func setICloudSync(_ on: Bool) {
        CloudSyncService.isEnabled = on
        iCloudSyncEnabled = on
        if on { syncFromCloud() }
    }

    /// リモートを取得してローカルとマージし、その後アップロード。
    /// item単位の last-writer-wins + トゥームストーンで削除も正しく伝播する。
    func syncFromCloud() {
        guard iCloudSyncEnabled, let key, let kind = activeKind else { return }
        Task {
            guard await CloudSyncService.shared.accountAvailable() else { return }
            if let blob = try? await CloudSyncService.shared.fetchBlob(kind: kind),
               let plain = try? CryptoService.decrypt(blob, key: key),
               let remote = try? JSONDecoder().decode(PersistedVault.self, from: plain) {
                let merged = Self.merge(
                    local: PersistedVault(items: items, tombstones: tombstones),
                    remote: remote
                )
                if merged.items != items || merged.tombstones != tombstones {
                    items = merged.items.sorted { $0.updatedAt > $1.updatedAt }
                    tombstones = merged.tombstones
                    persist()
                }
            }
            pushToCloud()
        }
    }

    private func pushToCloud() {
        guard iCloudSyncEnabled, let key, let kind = activeKind else { return }
        let snapshot = PersistedVault(items: items, tombstones: tombstones)
        Task {
            guard await CloudSyncService.shared.accountAvailable() else { return }
            if let data = try? JSONEncoder().encode(snapshot),
               let blob = try? CryptoService.encrypt(data, key: key) {
                try? await CloudSyncService.shared.uploadBlob(blob, kind: kind)
            }
        }
    }

    /// マージ規則:
    /// 1. トゥームストーンは両側の和集合（同一IDは新しい deletedAt を採用）。
    /// 2. itemは last-writer-wins（updatedAt が新しい方）。
    /// 3. トゥームストーンの deletedAt >= item の updatedAt なら削除が勝つ。
    ///    itemの方が新しい（削除後に別端末で編集された）場合はitemが勝ち、トゥームストーンを破棄。
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

    // MARK: - メモ CRUD

    func upsert(_ item: VaultItem) {
        guard key != nil, activeKind != nil else { return }
        var updated = item
        updated.updatedAt = Date()
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx] = updated
        } else {
            items.insert(updated, at: 0)
        }
        items.sort { $0.updatedAt > $1.updatedAt }
        // 復活させた場合に備え、同IDの墓標は除去
        tombstones.removeAll { $0.id == item.id }
        persist()
        pushToCloud()
    }

    func delete(ids: [UUID]) {
        guard key != nil, activeKind != nil else { return }
        let now = Date()
        for id in ids where items.contains(where: { $0.id == id }) {
            tombstones.append(Tombstone(id: id, deletedAt: now))
        }
        items.removeAll { ids.contains($0.id) }
        persist()
        pushToCloud()
    }

    func togglePin(_ id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].isPinned.toggle()
        items[idx].updatedAt = Date()
        persist()
        pushToCloud()
    }

    // MARK: - 設定

    /// PIN変更（現在開いている保管庫が対象）。
    func changePIN(to newPIN: String) -> Bool {
        guard let key, let kind = activeKind else { return false }
        if let (existing, _) = VaultManager.resolve(pin: newPIN), existing != kind {
            errorMessage = "そのPINは別の保管庫で使用中です"
            return false
        }
        do {
            self.key = try VaultManager.changePIN(kind: kind, oldKey: key, newPIN: newPIN)
            // 生体認証が有効なら、新しい鍵で保存し直す
            if kind == .primary, biometricEnabled {
                _ = enableBiometrics()
            }
            return true
        } catch {
            errorMessage = "PINの変更に失敗しました"
            return false
        }
    }

    /// おとり保管庫を作成/変更する。primaryとは別のPINが必要。
    func setupDecoy(pin: String) -> Bool {
        if let (existing, _) = VaultManager.resolve(pin: pin), existing != .decoy {
            errorMessage = "そのPINは本来の保管庫と重複しています"
            return false
        }
        do {
            if VaultManager.isSetup(.decoy) {
                VaultManager.removeVault(.decoy)
            }
            try VaultManager.create(kind: .decoy, pin: pin, seed: DecoySeed.items())
            return true
        } catch {
            errorMessage = "おとり保管庫の作成に失敗しました"
            return false
        }
    }

    func removeDecoy() {
        VaultManager.removeVault(.decoy)
        if iCloudSyncEnabled {
            Task { await CloudSyncService.shared.deleteBlob(kind: .decoy) }
        }
    }

    @discardableResult
    func enableBiometrics() -> Bool {
        guard activeKind == .primary, let key else { return false }
        let raw = key.withUnsafeBytes { Data($0) }
        let ok = BiometricKeyStore.save(key: raw)
        biometricEnabled = ok
        if !ok { errorMessage = "生体認証の設定に失敗しました" }
        return ok
    }

    func disableBiometrics() {
        BiometricKeyStore.remove()
        biometricEnabled = false
    }

    /// 緊急ワイプ: 全データを削除し、初期設定からやり直しになる。
    /// includeCloud=true なら iCloud 上の暗号文レコードも削除する。
    func wipeEverything(includeCloud: Bool = true) {
        if includeCloud && iCloudSyncEnabled {
            Task {
                await CloudSyncService.shared.deleteBlob(kind: .primary)
                await CloudSyncService.shared.deleteBlob(kind: .decoy)
            }
        }
        VaultManager.wipeAll()
        CloudSyncService.isEnabled = false
        key = nil
        activeKind = nil
        items = []
        tombstones = []
        biometricEnabled = false
        iCloudSyncEnabled = false
        errorMessage = nil
        phase = .needsSetup
    }
}
