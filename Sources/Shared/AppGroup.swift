import Foundation

/// アプリ本体・ウィジェット・共有拡張で共有する定数とヘルパ。
enum AppGroup {
    /// App Group ID（Signing & Capabilities で有効化し、各ターゲットに付与する）。
    static let identifier = "group.com.example.privacyvault"

    /// 共有 UserDefaults（機微でない集計のみを置く）。
    static var defaults: UserDefaults? {
        UserDefaults(suiteName: identifier)
    }

    /// 共有コンテナのルート。
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    // 機微でない集計（ウィジェット表示用）。メモ本文は一切含めない。
    enum Keys {
        static let noteCount = "widget.noteCount"
        static let lastUpdated = "widget.lastUpdated"   // Unix秒
    }

    /// ウィジェット用にメモ件数だけを書き出す（内容は書かない）。
    static func publishNoteCount(_ count: Int, updatedAt: Date) {
        defaults?.set(count, forKey: Keys.noteCount)
        defaults?.set(updatedAt.timeIntervalSince1970, forKey: Keys.lastUpdated)
    }

    static func readNoteCount() -> Int {
        defaults?.integer(forKey: Keys.noteCount) ?? 0
    }
}
