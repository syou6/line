import Foundation

enum BackupError: LocalizedError, Equatable {
    case wrongFormat
    case unsupportedVersion
    case wrongPassphrase

    var errorDescription: String? {
        switch self {
        case .wrongFormat: return "バックアップファイルの形式が正しくありません"
        case .unsupportedVersion: return "このバックアップは新しいバージョンで作成されています"
        case .wrongPassphrase: return "パスフレーズが違います"
        }
    }
}

/// バックアップファイルの外側の入れ物。JSON(Dataフィールドはbase64)で可搬。
struct BackupEnvelope: Codable, Equatable {
    var format: String
    var version: Int
    var salt: Data
    var ciphertext: Data
}

/// フォーマット定数とヘッダ検証（Foundationのみ・テスト可能）。
enum BackupFormat {
    static let format = "PrivacyVaultBackup"
    static let currentVersion = 1

    static func validateHeader(_ env: BackupEnvelope) throws {
        guard env.format == format else { throw BackupError.wrongFormat }
        guard env.version <= currentVersion else { throw BackupError.unsupportedVersion }
    }
}
