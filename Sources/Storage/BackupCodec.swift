import Foundation
import CryptoKit

/// パスフレーズで暗号化したバックアップの読み書き。
/// 本体はPIN鍵とは独立したパスフレーズ由来鍵(PBKDF2 + AES-GCM)で暗号化する。
enum BackupCodec {
    static func export(vault: PersistedVault, passphrase: String) throws -> Data {
        let salt = CryptoService.makeSalt()
        let key = CryptoService.deriveKey(pin: passphrase, salt: salt)
        let plain = try JSONEncoder().encode(vault)
        let cipher = try CryptoService.encrypt(plain, key: key)
        let env = BackupEnvelope(format: BackupFormat.format,
                                 version: BackupFormat.currentVersion,
                                 salt: salt, ciphertext: cipher)
        return try JSONEncoder().encode(env)
    }

    static func `import`(data: Data, passphrase: String) throws -> PersistedVault {
        let env = try JSONDecoder().decode(BackupEnvelope.self, from: data)
        try BackupFormat.validateHeader(env)
        let key = CryptoService.deriveKey(pin: passphrase, salt: env.salt)
        guard let plain = try? CryptoService.decrypt(env.ciphertext, key: key) else {
            throw BackupError.wrongPassphrase
        }
        return try JSONDecoder().decode(PersistedVault.self, from: plain)
    }
}
