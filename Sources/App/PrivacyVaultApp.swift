import SwiftUI

@main
struct PrivacyVaultApp: App {
    @StateObject private var state = AppState()
    @Environment(\.scenePhase) private var scenePhase
    @State private var backgroundedAt: Date?

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .tint(Theme.accent)
                .preferredColorScheme(.dark)
                // アプリスイッチャー等で中身が覗かれないよう、非アクティブ時は目隠し
                .overlay {
                    if scenePhase != .active {
                        PrivacyShade()
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: scenePhase)
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .background:
                backgroundedAt = Date()
            case .active:
                state.evaluateAutoLock(backgroundedAt: backgroundedAt)
                backgroundedAt = nil
            default:
                break
            }
        }
    }
}

/// 非アクティブ時に前面へ出す目隠しビュー。
struct PrivacyShade: View {
    var body: some View {
        ZStack {
            BrandBackground()
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 54))
                .foregroundStyle(Theme.accentSoft)
        }
        .ignoresSafeArea()
        .transition(.opacity)
    }
}
