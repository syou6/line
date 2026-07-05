import SwiftUI

@main
struct PrivacyVaultApp: App {
    @StateObject private var state = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { newPhase in
            // バックグラウンドに回ったら自動で施錠する。
            if newPhase == .background {
                state.lock()
            }
        }
    }
}
