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
    @Published private(set) var attempts: AttemptState
    @Published private(set) var autoWipeEnabled: Bool
    @Published var autoLockGrace: AutoLockGrace {
        didSet { UserDefaults.standard.set(autoLockGrace.rawValue, forKey: AutoLockGrace.storageKey) }
    }
    @Published var errorMessage: String?

    private var key: SymmetricKey?
    private var tombstones: [Tombstone] = []

    /// トゥームストーンの保持期間。これより古いものは保存時に破棄する。
    private static let tombstoneRetention: TimeInterval = 90 * 86_400

    private static let attemptsKey = "attemptState"
    private static let autoWipeKey = "autoWipeEnabled"
    /// 自動消去を有効にした場合の失敗回数しきい値。
    static let autoWipeThreshold = 10

    var biometricAvailable: Bool { BiometricKeyStore.isAvailable }
    var isDecoySession: Bool { activeKind == .decoy }
    var decoyConfigured: Bool { VaultManager.isSetup(.decoy) }

    private var lockoutPolicy: LockoutPolicy {
        LockoutPolicy(autoWipeAttempts: autoWipeEnabled ? Self.autoWipeThreshold : nil)
    }

    init() {
        phase = VaultManager.isSetup(.primary) ? .locked : .needsSetup
        biometricEnabled = BiometricKeyStore.isEnabled
        iCloudSyncEnabled = CloudSyncService.isEnabled
        InboxStore.ensureRecipientKey()  // 共有拡張が封をするための公開鍵を公開
        autoWipeEnabled = UserDefaults.standard.bool(forKey: Self.autoWipeKey)
        autoLockGrace = AutoLockGrace(rawValue: UserDefaults.standard.integer(forKey: AutoLockGrace.storageKey)) ?? .immediate
        if let data = UserDefaults.standard.data(forKey: Self.attemptsKey),
           let decoded = try? JSONDecoder().decode(AttemptState.self, from: data) {
            attempts = decoded
        } else {
            attempts = AttemptState()
        }
    }

    // MARK: - ロックアウト

    /// 現在のロックアウト残り秒（0なら解除済み）。
    func lockoutRemaining(now: Date = Date()) -> TimeInterval {
        attempts.remainingLockout(policy: lockoutPolicy, now: now)
    }

    private func persistAttempts() {
        if let data = try? JSONEncoder().encode(attempts) {
            UserDefaults.standard.set(data, forKey: Self.attemptsKey)
        }
    }

    private func registerFailure() {
        attempts.failed += 1
        attempts.lastFailure = Date()
        persistAttempts()
        if lockoutPolicy.shouldWipe(failedAttempts: attempts.failed) {
            wipeEverything()
        }
    }

    private func resetAttempts() {
        attempts = AttemptState()
        persistAttempts()
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
        let remaining = lockoutRemaining()
        if remaining > 0 {
            errorMessage = "試行回数が上限に達しました。\(Self.formatDuration(remaining))後に再試行できます。"
            return
        }
        // PBKDF2(20万回)は重いのでメインスレッドから逃がす
        Task.detached(priority: .userInitiated) {
            let resolved = VaultManager.resolve(pin: pin)
            await MainActor.run {
                guard let (kind, key) = resolved else {
                    self.registerFailure()
                    let left = self.lockoutRemaining()
                    if left > 0 {
                        self.errorMessage = "試行回数が上限に達しました。\(Self.formatDuration(left))後に再試行できます。"
                    } else {
                        self.errorMessage = "PINが違います"
                    }
                    return
                }
                self.resetAttempts()
                self.activate(kind: kind, key: key)
            }
        }
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        if s >= 60 { return "\(s / 60)分\(s % 60 > 0 ? "\(s % 60)秒" : "")" }
        return "\(s)秒"
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
        if kind == .primary { ingestInbox() }
        publishWidgetData()
        syncFromCloud()
    }

    /// 共有拡張から届いた下書きを取り込み、保管庫へ追加する（primaryのみ）。
    private func ingestInbox() {
        let drafts = InboxStore.drain()
        guard !drafts.isEmpty else { return }
        items.insert(contentsOf: drafts.map { $0.toVaultItem() }, at: 0)
        items.sort { $0.updatedAt > $1.updatedAt }
        persist()
        pushToCloud()
    }

    /// ウィジェット用に「件数」だけを共有領域へ公開する（内容は書かない・primaryのみ）。
    private func publishWidgetData() {
        guard activeKind == .primary else { return }
        AppGroup.publishNoteCount(items.count, updatedAt: Date())
    }

    /// 現在の items + tombstones をローカルに暗号化保存する。
    private func persist() {
        guard let key, let kind = activeKind else { return }
        let cutoff = Date().addingTimeInterval(-Self.tombstoneRetention)
        tombstones.removeAll { $0.deletedAt < cutoff }
        VaultManager.saveVault(PersistedVault(items: items, tombstones: tombstones), kind: kind, key: key)
        publishWidgetData()
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
                let merged = VaultMerge.merge(
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

    // MARK: - バックアップ

    /// 現在の保管庫をパスフレーズで暗号化してエクスポートする。
    func exportBackup(passphrase: String) -> Data? {
        let vault = PersistedVault(items: items, tombstones: tombstones)
        do {
            return try BackupCodec.export(vault: vault, passphrase: passphrase)
        } catch {
            errorMessage = "バックアップの作成に失敗しました"
            return nil
        }
    }

    /// バックアップを読み込み、現在の保管庫にマージする。
    /// 戻り値は取り込んだ（新規/更新された）メモ件数。失敗時は nil。
    func importBackup(data: Data, passphrase: String) -> Int? {
        guard let key, let kind = activeKind else { return nil }
        do {
            let incoming = try BackupCodec.import(data: data, passphrase: passphrase)
            let before = Set(items.map { $0.id })
            let merged = VaultMerge.merge(
                local: PersistedVault(items: items, tombstones: tombstones),
                remote: incoming
            )
            items = merged.items.sorted { $0.updatedAt > $1.updatedAt }
            tombstones = merged.tombstones
            VaultManager.saveVault(PersistedVault(items: items, tombstones: tombstones), kind: kind, key: key)
            pushToCloud()
            let added = items.filter { !before.contains($0.id) }.count
            return added
        } catch {
            errorMessage = (error as? BackupError)?.errorDescription ?? "読み込みに失敗しました"
            return nil
        }
    }

    // MARK: - 設定

    func setAutoWipe(_ on: Bool) {
        autoWipeEnabled = on
        UserDefaults.standard.set(on, forKey: Self.autoWipeKey)
    }

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
        resetAttempts()
        phase = .needsSetup
    }

    // MARK: - 自動ロック

    /// バックグラウンド復帰時、猶予を超えていれば施錠する。
    func evaluateAutoLock(backgroundedAt: Date?, now: Date = Date()) {
        guard phase == .unlocked else { return }
        if AutoLock.shouldLock(backgroundedAt: backgroundedAt, now: now, grace: autoLockGrace) {
            lock()
        }
    }
}
