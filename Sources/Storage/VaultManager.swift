import Foundation
import CryptoKit

/// 保管庫の作成・解錠・読み書きをまとめたファサード。
///
/// 保存物の内訳（種別ごと）:
/// - Keychain `salt.<kind>`     : PBKDF2用ソルト
/// - Keychain `verifier.<kind>` : 既知トークンを暗号化したもの（PIN照合用）
/// - File     `vault.<kind>.bin`: メモ本体を暗号化したもの
///
/// PINそのものやメモ平文は一切保存しない。
enum VaultManager {
    private static let verifierToken = Data("PRIVACY_VAULT_OK".utf8)

    private static func saltAccount(_ k: VaultKind) -> String { "salt.\(k.rawValue)" }
    private static func verifierAccount(_ k: VaultKind) -> String { "verifier.\(k.rawValue)" }
    private static func dataFile(_ k: VaultKind) -> String { "vault.\(k.rawValue).bin" }

    static func isSetup(_ k: VaultKind) -> Bool {
        KeychainStore.get(saltAccount(k)) != nil && KeychainStore.get(verifierAccount(k)) != nil
    }

    /// 新しい保管庫を作成する。seed を渡すと初期メモを入れて作成する。
    static func create(kind: VaultKind, pin: String, seed: [VaultItem] = []) throws {
        let salt = CryptoService.makeSalt()
        let key = CryptoService.deriveKey(pin: pin, salt: salt)
        let verifier = try CryptoService.encrypt(verifierToken, key: key)
        let data = try JSONEncoder().encode(PersistedVault(items: seed))
        let blob = try CryptoService.encrypt(data, key: key)

        KeychainStore.set(salt, for: saltAccount(kind))
        KeychainStore.set(verifier, for: verifierAccount(kind))
        FileStore.write(blob, name: dataFile(kind))
    }

    /// 入力PINに一致する保管庫を探し、(種別, 鍵) を返す。なければnil。
    /// primary/decoy のどちらでも、一致した方を開く。
    static func resolve(pin: String) -> (VaultKind, SymmetricKey)? {
        for kind in VaultKind.allCases where isSetup(kind) {
            guard let salt = KeychainStore.get(saltAccount(kind)),
                  let verifier = KeychainStore.get(verifierAccount(kind)) else { continue }

            let key = CryptoService.deriveKey(pin: pin, salt: salt)
            if let decrypted = try? CryptoService.decrypt(verifier, key: key),
               decrypted == verifierToken {
                return (kind, key)
            }
        }
        return nil
    }

    /// 指定PINがいずれかの保管庫で既に使われているか（重複PIN防止用）。
    static func pinInUse(_ pin: String) -> Bool {
        resolve(pin: pin) != nil
    }

    static func loadVault(kind: VaultKind, key: SymmetricKey) -> PersistedVault {
        guard let blob = FileStore.read(dataFile(kind)),
              let plain = try? CryptoService.decrypt(blob, key: key),
              let vault = try? JSONDecoder().decode(PersistedVault.self, from: plain) else {
            return PersistedVault(items: [])
        }
        return vault
    }

    @discardableResult
    static func saveVault(_ vault: PersistedVault, kind: VaultKind, key: SymmetricKey) -> Bool {
        guard let data = try? JSONEncoder().encode(vault),
              let blob = try? CryptoService.encrypt(data, key: key) else { return false }
        return FileStore.write(blob, name: dataFile(kind))
    }

    /// PIN変更: 新しいソルト・鍵で検証トークンと本体を暗号化し直す。
    static func changePIN(kind: VaultKind, oldKey: SymmetricKey, newPIN: String) throws -> SymmetricKey {
        let vault = loadVault(kind: kind, key: oldKey)
        let salt = CryptoService.makeSalt()
        let newKey = CryptoService.deriveKey(pin: newPIN, salt: salt)
        let verifier = try CryptoService.encrypt(verifierToken, key: newKey)

        KeychainStore.set(salt, for: saltAccount(kind))
        KeychainStore.set(verifier, for: verifierAccount(kind))
        saveVault(vault, kind: kind, key: newKey)
        return newKey
    }

    static func removeVault(_ kind: VaultKind) {
        KeychainStore.delete(saltAccount(kind))
        KeychainStore.delete(verifierAccount(kind))
        FileStore.delete(dataFile(kind))
    }

    /// 全消去（緊急ワイプ）。すべての保管庫・鍵・生体認証設定を削除する。
    static func wipeAll() {
        KeychainStore.deleteAll()
        BiometricKeyStore.remove()
        FileStore.deleteAll()
    }

}
