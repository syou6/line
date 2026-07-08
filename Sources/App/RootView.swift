import SwiftUI

struct RootView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        switch state.phase {
        case .needsSetup:
            SetupView()
        case .locked:
            LockView()
        case .unlocked:
            MainView()
        }
    }
}

/// 解錠後のメイン画面。メモ一覧 + 設定のタブ。
struct MainView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        TabView {
            VaultListView()
                .tabItem { Label("メモ", systemImage: "lock.doc") }
            SettingsView()
                .tabItem { Label("設定", systemImage: "gearshape") }
        }
    }
}
