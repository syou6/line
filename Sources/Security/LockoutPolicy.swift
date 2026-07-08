import Foundation

/// 誤PIN入力に対するロックアウト方針（純粋ロジック・テスト可能）。
struct LockoutPolicy: Equatable {
    /// この回数までは遅延なし。
    var freeAttempts: Int = 5
    /// 到達で全データを自動消去する失敗回数。nil で無効。
    var autoWipeAttempts: Int? = nil
    /// バックオフの上限（秒）。
    var maxDelay: TimeInterval = 3600

    /// 失敗回数に対する必要待機時間。freeAttempts 超過分で 30s から倍々に増える。
    func lockoutDuration(failedAttempts: Int) -> TimeInterval {
        guard failedAttempts > freeAttempts else { return 0 }
        let over = failedAttempts - freeAttempts            // 1, 2, 3, ...
        let secs = 30.0 * pow(2.0, Double(over - 1))        // 30, 60, 120, ...
        return min(secs, maxDelay)
    }

    func shouldWipe(failedAttempts: Int) -> Bool {
        guard let w = autoWipeAttempts else { return false }
        return failedAttempts >= w
    }
}

/// 失敗回数と最終失敗時刻から、ロックアウトの残り時間を計算する。
struct AttemptState: Codable, Equatable {
    var failed: Int = 0
    var lastFailure: Date? = nil

    /// 現在ロックアウト中なら解除時刻を返す。
    func lockedUntil(policy: LockoutPolicy) -> Date? {
        guard let last = lastFailure else { return nil }
        let duration = policy.lockoutDuration(failedAttempts: failed)
        guard duration > 0 else { return nil }
        return last.addingTimeInterval(duration)
    }

    /// now 時点の残りロックアウト秒（0以下なら解除済み）。
    func remainingLockout(policy: LockoutPolicy, now: Date) -> TimeInterval {
        guard let until = lockedUntil(policy: policy) else { return 0 }
        return max(0, until.timeIntervalSince(now))
    }

    func isLockedOut(policy: LockoutPolicy, now: Date) -> Bool {
        remainingLockout(policy: policy, now: now) > 0
    }
}
