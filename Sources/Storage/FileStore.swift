import Foundation

/// 暗号化済みの保管庫 blob をアプリ専用ディレクトリに保存する。
/// ファイル保護属性 completeFileProtection を付与し、端末ロック中は読めないようにする。
enum FileStore {
    private static func directory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("vault", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func url(for name: String) -> URL {
        directory().appendingPathComponent(name)
    }

    @discardableResult
    static func write(_ data: Data, name: String) -> Bool {
        do {
            try data.write(to: url(for: name), options: [.atomic, .completeFileProtection])
            return true
        } catch {
            return false
        }
    }

    static func read(_ name: String) -> Data? {
        try? Data(contentsOf: url(for: name))
    }

    static func delete(_ name: String) {
        try? FileManager.default.removeItem(at: url(for: name))
    }

    static func deleteAll() {
        try? FileManager.default.removeItem(at: directory())
    }
}
