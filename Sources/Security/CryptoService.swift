import Foundation
import CommonCrypto
import CryptoKit
import Security

enum CryptoError: Error {
    case sealFailed
}

/// 暗号化まわりの純粋関数群。
/// - 鍵: PIN + ランダムソルトから PBKDF2 (HMAC-SHA256) で導出。
/// - 暗号化: AES-GCM (CryptoKit)。
enum CryptoService {

    /// 暗号学的に安全な乱数ソルトを生成する。
    static func makeSalt(_ count: Int = 16) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }

    /// PINとソルトから256bitの対称鍵を導出する。
    /// ラウンド数を大きく取ることで、桁数の少ないPINでも総当たりを重くする。
    static func deriveKey(pin: String, salt: Data, rounds: Int = 200_000) -> SymmetricKey {
        let pinBytes = Array(pin.utf8)
        var derived = [UInt8](repeating: 0, count: 32)

        salt.withUnsafeBytes { saltRaw in
            let saltPtr = saltRaw.bindMemory(to: UInt8.self).baseAddress
            pinBytes.withUnsafeBufferPointer { pinBuf in
                pinBuf.baseAddress!.withMemoryRebound(to: Int8.self, capacity: pinBytes.count) { pinPtr in
                    _ = CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pinPtr, pinBytes.count,
                        saltPtr, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(rounds),
                        &derived, derived.count
                    )
                }
            }
        }
        return SymmetricKey(data: Data(derived))
    }

    static func encrypt(_ plaintext: Data, key: SymmetricKey) throws -> Data {
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else { throw CryptoError.sealFailed }
        return combined
    }

    static func decrypt(_ ciphertext: Data, key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: ciphertext)
        return try AES.GCM.open(box, using: key)
    }
}
