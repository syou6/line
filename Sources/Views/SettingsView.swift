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
            ZStack {
                BrandBackground()
                Form {
                    securitySection
                    if state.biometricAvailable && !state.isDecoySession {
                        biometricSection
                    }
                    iCloudSection
                    if !state.isDecoySession {
                        decoySection
                    }
                    wipeSection
                }
                .scrollContentBackground(.hidden)
                .tint(Theme.accent)
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
            .overlay(alignment: .bottom) { toastView }
        }
    }

    // MARK: - Sections

    private var securitySection: some View {
        Section("セキュリティ") {
            Button {
                state.lock()
            } label: {
                settingRow("今すぐロック", systemImage: "lock.fill", tint: Theme.accent)
            }
            Button {
                showChangePIN = true
            } label: {
                settingRow("PINを変更", systemImage: "key.fill", tint: Theme.accent)
            }
        }
    }

    private var biometricSection: some View {
        Section {
            Toggle(isOn: biometricBinding) {
                settingRow("生体認証で解錠", systemImage: "faceid", tint: Theme.accent)
            }
        } footer: {
            Text("Face ID / Touch ID でロックを解除します。鍵は生体認証付きのKeychainに保管されます。")
        }
    }

    private var iCloudSection: some View {
        Section {
            Toggle(isOn: iCloudBinding) {
                settingRow("iCloud同期", systemImage: "icloud.fill", tint: Theme.accent)
            }
            if state.iCloudSyncEnabled {
                Button {
                    state.syncFromCloud()
                    toast = "同期しました"
                } label: {
                    settingRow("今すぐ同期", systemImage: "arrow.triangle.2.circlepath", tint: Theme.accent)
                }
            }
        } header: {
            Text("iCloud")
        } footer: {
            Text("メモは端末内で暗号化してから同期するため、クラウド上には暗号文しか保存されません。同じPINを設定した端末どうしで内容を共有できます。")
        }
    }

    private var decoySection: some View {
        Section {
            if state.decoyConfigured {
                Button { showDecoySetup = true } label: {
                    settingRow("おとりPINを変更", systemImage: "eye.slash.fill", tint: .orange)
                }
                Button(role: .destructive) { confirmRemoveDecoy = true } label: {
                    settingRow("おとり保管庫を削除", systemImage: "trash.fill", tint: .red)
                }
            } else {
                Button { showDecoySetup = true } label: {
                    settingRow("おとりPINを設定", systemImage: "eye.slash.fill", tint: .orange)
                }
            }
        } header: {
            Text("おとり保管庫")
        } footer: {
            Text("本来のPINとは別のPINを設定できます。そのPINを入力すると、本来の内容とは切り離された別の保管庫が開きます。PINの開示を強要された場合などに本来の内容を守るための機能です。")
        }
    }

    private var wipeSection: some View {
        Section {
            Button(role: .destructive) { confirmWipe = true } label: {
                settingRow("全データを消去", systemImage: "exclamationmark.triangle.fill", tint: .red)
            }
        } footer: {
            Text("すべての保管庫・メモ・鍵を端末（および同期済みならiCloud）から完全に削除します。取り消せません。")
        }
    }

    // MARK: - Parts

    private func settingRow(_ title: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.9), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(title)
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            Text(toast)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.surfaceStroke, lineWidth: 1))
                .padding(.bottom, 28)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    withAnimation { self.toast = nil }
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

    private var iCloudBinding: Binding<Bool> {
        Binding(
            get: { state.iCloudSyncEnabled },
            set: { state.setICloudSync($0) }
        )
    }
}
