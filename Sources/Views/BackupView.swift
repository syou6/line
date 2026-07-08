import SwiftUI
import UniformTypeIdentifiers

/// バックアップの書き出し／読み込みシート。
struct BackupView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode = .export
    @State private var passphrase = ""
    @State private var confirmPassphrase = ""
    @State private var exportDoc: BackupDocument?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var message: String?

    enum Mode: String, CaseIterable {
        case export = "書き出し"
        case restore = "読み込み"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BrandBackground()
                Form {
                    Picker("", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)

                    Section {
                        SecureField("パスフレーズ", text: $passphrase)
                        if mode == .export {
                            SecureField("パスフレーズ（確認）", text: $confirmPassphrase)
                        }
                    } footer: {
                        Text(mode == .export
                             ? "このパスフレーズはバックアップの暗号化に使います。忘れると復元できません（PINとは別に設定できます）。"
                             : "書き出し時に設定したパスフレーズを入力してください。読み込んだメモは現在の保管庫にマージされます。")
                    }

                    Section {
                        Button(action: primaryAction) {
                            Label(mode == .export ? "暗号化して書き出す" : "ファイルを選んで読み込む",
                                  systemImage: mode == .export ? "square.and.arrow.up" : "square.and.arrow.down")
                        }
                        .disabled(!canProceed)
                    }

                    if let message {
                        Section {
                            Text(LocalizedStringKey(message))
                                .font(.footnote)
                                .foregroundStyle(Theme.accentSoft)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("バックアップ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .fileExporter(
                isPresented: $showExporter,
                document: exportDoc,
                contentType: .json,
                defaultFilename: "privatememo-backup"
            ) { result in
                if case .success = result { message = "書き出しました。安全な場所に保管してください。" }
                else { message = "書き出しをキャンセルしました。" }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.json, .data]
            ) { result in
                handleImport(result)
            }
        }
    }

    private var canProceed: Bool {
        guard !passphrase.isEmpty else { return false }
        if mode == .export { return passphrase == confirmPassphrase }
        return true
    }

    private func primaryAction() {
        message = nil
        switch mode {
        case .export:
            guard let data = state.exportBackup(passphrase: passphrase) else {
                message = state.errorMessage ?? "書き出しに失敗しました"
                return
            }
            exportDoc = BackupDocument(data: data)
            showExporter = true
        case .restore:
            showImporter = true
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let needsStop = url.startAccessingSecurityScopedResource()
            defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                message = "ファイルを読み込めませんでした"
                return
            }
            if let added = state.importBackup(data: data, passphrase: passphrase) {
                message = "読み込み完了：\(added)件を追加しました。"
            } else {
                message = state.errorMessage ?? "読み込みに失敗しました"
            }
        case .failure:
            message = "ファイル選択をキャンセルしました。"
        }
    }
}

/// エクスポート用の FileDocument（暗号化済みJSON）。
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
