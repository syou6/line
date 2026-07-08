import SwiftUI

/// 解錠画面。正しいPINでprimary、おとりPINでdecoyが開く。
struct LockView: View {
    @EnvironmentObject private var state: AppState
    @State private var now = Date()

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var lockoutRemaining: TimeInterval { state.lockoutRemaining(now: now) }
    private var isLockedOut: Bool { lockoutRemaining > 0 }

    var body: some View {
        ZStack {
            BrandBackground()
            VStack {
                if isLockedOut {
                    lockoutView
                } else {
                    PINEntryView(
                        title: "ロック解除",
                        subtitle: "PINを入力してください",
                        showBiometric: state.biometricEnabled && state.biometricAvailable,
                        onBiometric: { state.unlockWithBiometrics() }
                    ) { pin in
                        state.unlock(pin: pin)
                    }

                    if let msg = state.errorMessage {
                        Text(msg)
                            .font(.footnote)
                            .foregroundStyle(Theme.accentSoft)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                            .padding(.bottom)
                    }
                }
            }
        }
        .onReceive(ticker) { now = $0 }
        .onAppear {
            if state.biometricEnabled && state.biometricAvailable && !isLockedOut {
                state.unlockWithBiometrics()
            }
        }
    }

    private var lockoutView: some View {
        VStack(spacing: 20) {
            Image(systemName: "hourglass")
                .font(.system(size: 48))
                .foregroundStyle(Theme.accentSoft)
            Text("試行回数が上限に達しました")
                .font(.headline)
                .foregroundStyle(.white)
            Text("あと \(AppState.formatDuration(lockoutRemaining)) 待ってください")
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.accentSoft)
            Text("誤ったPINが\(state.attempts.failed)回入力されました。")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(40)
    }
}
