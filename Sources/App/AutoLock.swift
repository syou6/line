import Foundation

/// 自動ロックの猶予時間。
enum AutoLockGrace: Int, CaseIterable, Identifiable {
    case immediate = 0
    case oneMinute = 60
    case fiveMinutes = 300

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .immediate: return "即時"
        case .oneMinute: return "1分後"
        case .fiveMinutes: return "5分後"
        }
    }

    static let storageKey = "autoLockGrace"
}

/// バックグラウンド移行時刻・復帰時刻・猶予から、施錠すべきか判定する（純粋ロジック）。
enum AutoLock {
    static func shouldLock(backgroundedAt: Date?, now: Date, grace: AutoLockGrace) -> Bool {
        if grace == .immediate { return true }
        guard let bg = backgroundedAt else { return false }
        return now.timeIntervalSince(bg) >= Double(grace.rawValue)
    }
}
