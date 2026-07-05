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
    @Published var errorMessage: String?

    private var key: SymmetricKey?

    var biometricAvailable: Bool { BiometricKeyStore.isAvailable }
    var isDecoySession: Bool { activeKind == .decoy }
    var decoyConfigured: Bool { VaultManager.isSetup(.decoy) }

    init() {
        phase = VaultManager.isSetup(.primary) ? .locked : .needsSetup
        biometricEnabled = BiometricKeyStore.isEnabled
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
        errorMessage = nil
        phase = .locked
    }

    private func activate(kind: VaultKind, key: SymmetricKey) {
        self.key = key
        self.activeKind = kind
        self.items = VaultManager.loadItems(kind: kind, key: key)
        self.errorMessage = nil
        self.phase = .unlocked
    }

    // MARK: - メモ CRUD

    func upsert(_ item: VaultItem) {
        guard let key, let kind = activeKind else { return }
        var updated = item
        updated.updatedAt = Date()
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx] = updated
        } else {
            items.insert(updated, at: 0)
        }
        items.sort { $0.updatedAt > $1.updatedAt }
        VaultManager.saveItems(items, kind: kind, key: key)
    }

    func delete(at offsets: IndexSet) {
        guard let key, let kind = activeKind else { return }
        items.remove(atOffsets: offsets)
        VaultManager.saveItems(items, kind: kind, key: key)
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
            try VaultManager.create(kind: .decoy, pin: pin)
            return true
        } catch {
            errorMessage = "おとり保管庫の作成に失敗しました"
            return false
        }
    }

    func removeDecoy() {
        VaultManager.removeVault(.decoy)
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
    func wipeEverything() {
        VaultManager.wipeAll()
        key = nil
        activeKind = nil
        items = []
        biometricEnabled = false
        errorMessage = nil
        phase = .needsSetup
    }
}
