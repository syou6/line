import SwiftUI

/// 入力 → 確認 の2段階で新しいPINを決めるシート。
/// 一致したPINを onDone(pin) で返す。
struct PINSetupSheet: View {
    let title: String
    var subtitle: String? = nil
    let onDone: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var first: String?
    @State private var mismatch = false

    var body: some View {
        NavigationStack {
            VStack {
                if let first {
                    PINEntryView(title: "確認のためもう一度", subtitle: subtitle) { confirm in
                        if confirm == first {
                            onDone(confirm)
                            dismiss()
                        } else {
                            self.first = nil
                            mismatch = true
                        }
                    }
                } else {
                    PINEntryView(title: title, subtitle: subtitle) { pin in
                        first = pin
                        mismatch = false
                    }
                }

                if mismatch {
                    Text("PINが一致しませんでした")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.bottom)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
        }
    }
}
