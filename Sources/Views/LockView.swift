import SwiftUI

/// 解錠画面。正しいPINでprimary、おとりPINでdecoyが開く。
struct LockView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack {
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
                    .foregroundStyle(.red)
                    .padding(.bottom)
            }
        }
        .onAppear {
            // 生体認証が有効なら自動でプロンプトを出す
            if state.biometricEnabled && state.biometricAvailable {
                state.unlockWithBiometrics()
            }
        }
    }
}
