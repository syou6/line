import Foundation
import Security
import LocalAuthentication

/// primary保管庫の鍵を「生体認証でのみ取り出せる」形でKeychainに保存する。
/// SecItemの読み出し時に Face ID / Touch ID が要求される。
enum BiometricKeyStore {
    static let service = "com.example.privacyvault.biometric"
    static let account = "primary-key"
    static let enabledFlag = "biometricEnabled"

    /// 端末が生体認証に対応しているか（登録済みか）。
    static var isAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// ユーザーが生体認証ロック解除を有効にしているか（プロンプトを出さずに判定）。
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledFlag)
    }

    static func save(key: Data) -> Bool {
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            .biometryCurrentSet,
            &error
        ) else {
            return false
        }

        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)

        var attrs = base
        attrs[kSecValueData as String] = key
        attrs[kSecAttrAccessControl as String] = access

        let ok = SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
        if ok { UserDefaults.standard.set(true, forKey: enabledFlag) }
        return ok
    }

    /// 生体認証を要求して鍵を取り出す。失敗時はnil。
    /// Keychainへのアクセスがブロッキングなので、呼び出し側はバックグラウンドで実行すること。
    static func load(reason: String) -> Data? {
        let context = LAContext()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context,
            kSecUseOperationPrompt as String: reason
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    static func remove() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.set(false, forKey: enabledFlag)
    }
}
