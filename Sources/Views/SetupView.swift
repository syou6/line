import SwiftUI

/// 初回起動時のPIN設定。入力 → 確認の2段階。
struct SetupView: View {
    @EnvironmentObject private var state: AppState
    @State private var firstPIN: String?

    var body: some View {
        ZStack {
            BrandBackground()
            VStack {
                if let first = firstPIN {
                    PINEntryView(
                        title: "PINの確認",
                        subtitle: "もう一度同じ6桁を入力してください"
                    ) { confirm in
                        if confirm == first {
                            state.setupPrimary(pin: confirm)
                        } else {
                            firstPIN = nil
                            state.errorMessage = "PINが一致しませんでした。最初からやり直してください。"
                        }
                    }
                } else {
                    PINEntryView(
                        title: "PINを作成",
                        subtitle: "メモの暗号化に使う6桁のPINを決めてください"
                    ) { pin in
                        firstPIN = pin
                        state.errorMessage = nil
                    }
                }

                if let msg = state.errorMessage {
                    Text(msg)
                        .font(.footnote)
                        .foregroundStyle(Theme.accentSoft)
                        .padding(.bottom)
                }
            }
        }
    }
}
