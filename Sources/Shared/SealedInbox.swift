import Foundation
import CryptoKit
import Security

/// 公開鍵で封をする一方向シールドボックス（X25519 + HKDF-SHA256 + AES-GCM）。
/// 共有拡張は本体アプリの公開鍵で封をするだけで、開封（復号）は本体アプリの秘密鍵でのみ可能。
enum SealedBoxCrypto {
    private static let info = Data("PrivacyVaultInbox".utf8)

    static func seal(_ plaintext: Data, to recipientPublicKey: Curve25519.KeyAgreement.PublicKey) throws -> Data {
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let shared = try ephemeral.sharedSecretFromKeyAgreement(with: recipientPublicKey)
        let symKey = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data(), sharedInfo: info, outputByteCount: 32)
        let box = try AES.GCM.seal(plaintext, using: symKey)
        guard let combined = box.combined else { throw CryptoError.sealFailed }
        return ephemeral.publicKey.rawRepresentation + combined
    }

    static func open(_ data: Data, with recipientPrivateKey: Curve25519.KeyAgreement.PrivateKey) throws -> Data {
        let pubData = data.prefix(32)
        let rest = data.dropFirst(32)
        let ephPub = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: pubData)
        let shared = try recipientPrivateKey.sharedSecretFromKeyAgreement(with: ephPub)
        let symKey = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data(), sharedInfo: info, outputByteCount: 32)
        let box = try AES.GCM.SealedBox(combined: rest)
        return try AES.GCM.open(box, using: symKey)
    }
}

/// 受信箱の鍵管理と読み書き。
/// - 受信者(本体)の秘密鍵: 本体アプリのKeychainにのみ保存。
/// - 受信者の公開鍵: App Group の共有領域に置き、共有拡張から読めるようにする（公開鍵なので秘匿不要）。
/// - 封じた下書き: App Group コンテナの inbox/ に1件1ファイルで置く。
enum InboxStore {
    private static let privateKeyAccount = "inbox.privateKey"
    private static let publicKeyDefault = "inbox.publicKey"
    private static let inboxDir = "inbox"

    // MARK: 本体アプリ側

    /// 受信者キーペアを用意し、公開鍵をApp Groupへ公開する（本体アプリ起動時に呼ぶ）。
    static func ensureRecipientKey() {
        let priv = loadOrCreatePrivateKey()
        AppGroup.defaults?.set(priv.publicKey.rawRepresentation, forKey: publicKeyDefault)
    }

    private static func loadOrCreatePrivateKey() -> Curve25519.KeyAgreement.PrivateKey {
        if let raw = KeychainStore.get(privateKeyAccount),
           let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: raw) {
            return key
        }
        let key = Curve25519.KeyAgreement.PrivateKey()
        KeychainStore.set(key.rawRepresentation, for: privateKeyAccount)
        return key
    }

    /// 受信箱の封じられた下書きをすべて開封して返し、ファイルを削除する（本体アプリの解錠時）。
    static func drain() -> [InboxDraft] {
        guard let dir = inboxURL() else { return [] }
        guard let priv = try? Curve25519.KeyAgreement.PrivateKey(
            rawRepresentation: KeychainStore.get(privateKeyAccount) ?? Data()) else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var drafts: [InboxDraft] = []
        for url in files where url.pathExtension == "seal" {
            if let sealed = try? Data(contentsOf: url),
               let plain = try? SealedBoxCrypto.open(sealed, with: priv),
               let draft = try? InboxCodec.decode(plain) {
                drafts.append(draft)
            }
            try? FileManager.default.removeItem(at: url)
        }
        return drafts.sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: 共有拡張側

    /// 共有拡張から下書きを封じて受信箱へ追加する。公開鍵が未公開なら false。
    @discardableResult
    static func enqueue(_ draft: InboxDraft) -> Bool {
        guard let pubData = AppGroup.defaults?.data(forKey: publicKeyDefault),
              let pub = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: pubData),
              let dir = inboxURL() else { return false }
        do {
            let plain = try InboxCodec.encode(draft)
            let sealed = try SealedBoxCrypto.seal(plain, to: pub)
            let url = dir.appendingPathComponent("\(draft.id.uuidString).seal")
            try sealed.write(to: url, options: [.completeFileProtection])
            return true
        } catch {
            return false
        }
    }

    private static func inboxURL() -> URL? {
        guard let base = AppGroup.containerURL else { return nil }
        let dir = base.appendingPathComponent(inboxDir, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
