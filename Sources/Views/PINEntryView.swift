import SwiftUI

/// 再利用可能な6桁PIN入力ビュー。
/// 6桁揃うと onComplete が呼ばれ、入力はリセットされる。
struct PINEntryView: View {
    let title: String
    var subtitle: String? = nil
    var showBiometric: Bool = false
    var onBiometric: (() -> Void)? = nil
    let onComplete: (String) -> Void

    @State private var pin: String = ""
    private let maxLen = 6

    private let keys: [String] = ["1","2","3","4","5","6","7","8","9","bio","0","del"]

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 8)

            Image(systemName: "lock.shield")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.tint)

            VStack(spacing: 6) {
                Text(title)
                    .font(.title3.weight(.semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            dots

            pad

            Spacer(minLength: 8)
        }
        .padding()
        .onChange(of: pin) { value in
            if value.count == maxLen {
                let entered = value
                // 次の入力に備えて即クリア
                DispatchQueue.main.async { pin = "" }
                onComplete(entered)
            }
        }
    }

    private var dots: some View {
        HStack(spacing: 18) {
            ForEach(0..<maxLen, id: \.self) { i in
                Circle()
                    .strokeBorder(Color.secondary, lineWidth: 1.5)
                    .background(Circle().fill(i < pin.count ? Color.accentColor : Color.clear))
                    .frame(width: 16, height: 16)
            }
        }
        .frame(height: 20)
    }

    private var pad: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 24), count: 3)
        return LazyVGrid(columns: columns, spacing: 20) {
            ForEach(keys, id: \.self) { keyLabel in
                keyButton(keyLabel)
            }
        }
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private func keyButton(_ label: String) -> some View {
        switch label {
        case "del":
            Button {
                if !pin.isEmpty { pin.removeLast() }
            } label: {
                Image(systemName: "delete.left")
                    .font(.title2)
                    .frame(width: 72, height: 72)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)

        case "bio":
            if showBiometric {
                Button {
                    onBiometric?()
                } label: {
                    Image(systemName: "faceid")
                        .font(.title2)
                        .frame(width: 72, height: 72)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            } else {
                Color.clear.frame(width: 72, height: 72)
            }

        default:
            Button {
                if pin.count < maxLen { pin.append(label) }
            } label: {
                Text(label)
                    .font(.title.weight(.regular))
                    .frame(width: 72, height: 72)
                    .background(Circle().fill(Color.secondary.opacity(0.15)))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
        }
    }
}
