import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState

    @State private var showChangePIN = false
    @State private var showDecoySetup = false
    @State private var confirmWipe = false
    @State private var confirmRemoveDecoy = false
    @State private var toast: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("セキュリティ") {
                    Button {
                        state.lock()
                    } label: {
                        Label("今すぐロック", systemImage: "lock")
                    }

                    Button {
                        showChangePIN = true
                    } label: {
                        Label("PINを変更", systemImage: "key")
                    }

                    if state.biometricAvailable && !state.isDecoySession {
                        Toggle(isOn: biometricBinding) {
                            Label("生体認証で解錠", systemImage: "faceid")
                        }
                    }
                }

                if !state.isDecoySession {
                    Section {
                        if state.decoyConfigured {
                            Button {
                                showDecoySetup = true
                            } label: {
                                Label("おとりPINを変更", systemImage: "eye.slash")
                            }
                            Button(role: .destructive) {
                                confirmRemoveDecoy = true
                            } label: {
                                Label("おとり保管庫を削除", systemImage: "trash")
                            }
                        } else {
                            Button {
                                showDecoySetup = true
                            } label: {
                                Label("おとりPINを設定", systemImage: "eye.slash")
                            }
                        }
                    } header: {
                        Text("おとり保管庫")
                    } footer: {
                        Text("本来のPINとは別のPINを設定できます。そのPINを入力すると、本来の内容とは切り離された別の空の保管庫が開きます。PINの開示を強要された場合などに、本来の保管庫を守るための機能です。")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        confirmWipe = true
                    } label: {
                        Label("全データを消去", systemImage: "exclamationmark.triangle")
                    }
                } footer: {
                    Text("すべての保管庫・メモ・鍵を端末から完全に削除します。取り消せません。")
                }
            }
            .navigationTitle("設定")
            .sheet(isPresented: $showChangePIN) {
                PINSetupSheet(title: "新しいPIN", subtitle: "この保管庫の新しい6桁PIN") { pin in
                    toast = state.changePIN(to: pin) ? "PINを変更しました" : (state.errorMessage ?? "変更できませんでした")
                }
            }
            .sheet(isPresented: $showDecoySetup) {
                PINSetupSheet(title: "おとりPIN", subtitle: "本来のPINとは別の6桁") { pin in
                    toast = state.setupDecoy(pin: pin) ? "おとり保管庫を設定しました" : (state.errorMessage ?? "設定できませんでした")
                }
            }
            .alert("全データを消去しますか？", isPresented: $confirmWipe) {
                Button("消去する", role: .destructive) { state.wipeEverything() }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("すべての保管庫とメモが完全に削除されます。この操作は取り消せません。")
            }
            .alert("おとり保管庫を削除しますか？", isPresented: $confirmRemoveDecoy) {
                Button("削除する", role: .destructive) {
                    state.removeDecoy()
                    toast = "おとり保管庫を削除しました"
                }
                Button("キャンセル", role: .cancel) {}
            }
            .overlay(alignment: .bottom) {
                if let toast {
                    Text(toast)
                        .font(.footnote)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.thinMaterial, in: Capsule())
                        .padding(.bottom, 24)
                        .transition(.opacity)
                        .task {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            self.toast = nil
                        }
                }
            }
        }
    }

    private var biometricBinding: Binding<Bool> {
        Binding(
            get: { state.biometricEnabled },
            set: { on in
                if on { state.enableBiometrics() } else { state.disableBiometrics() }
            }
        )
    }
}
