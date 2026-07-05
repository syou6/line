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
        VStack(spacing: 30) {
            Spacer(minLength: 8)

            emblem

            VStack(spacing: 6) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.6))
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
                DispatchQueue.main.async { pin = "" }
                onComplete(entered)
            }
        }
    }

    private var emblem: some View {
        ZStack {
            Circle()
                .fill(Theme.accentGradient)
                .frame(width: 84, height: 84)
                .shadow(color: Theme.accent.opacity(0.5), radius: 18, y: 6)
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(.white)
        }
    }

    private var dots: some View {
        HStack(spacing: 20) {
            ForEach(0..<maxLen, id: \.self) { i in
                Circle()
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5)
                    .background(
                        Circle().fill(i < pin.count ? Theme.accent : Color.clear)
                    )
                    .frame(width: 15, height: 15)
                    .shadow(color: i < pin.count ? Theme.accent.opacity(0.7) : .clear, radius: 6)
                    .animation(.spring(response: 0.25, dampingFraction: 0.6), value: pin.count)
            }
        }
        .frame(height: 20)
    }

    private var pad: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 26), count: 3)
        return LazyVGrid(columns: columns, spacing: 22) {
            ForEach(keys, id: \.self) { keyLabel in
                keyButton(keyLabel)
            }
        }
        .padding(.horizontal, 28)
    }

    @ViewBuilder
    private func keyButton(_ label: String) -> some View {
        switch label {
        case "del":
            padButton(filled: false) {
                if !pin.isEmpty { pin.removeLast() }
            } content: {
                Image(systemName: "delete.left")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.85))
            }

        case "bio":
            if showBiometric {
                padButton(filled: false) {
                    onBiometric?()
                } content: {
                    Image(systemName: "faceid")
                        .font(.title2)
                        .foregroundStyle(Theme.accentSoft)
                }
            } else {
                Color.clear.frame(width: 74, height: 74)
            }

        default:
            padButton(filled: true) {
                if pin.count < maxLen { pin.append(label) }
            } content: {
                Text(label)
                    .font(.title.weight(.regular))
                    .foregroundStyle(.white)
            }
        }
    }

    private func padButton<C: View>(
        filled: Bool,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> C
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(filled ? Color.white.opacity(0.08) : Color.clear)
                    .overlay(
                        Circle().strokeBorder(Color.white.opacity(filled ? 0.12 : 0), lineWidth: 1)
                    )
                content()
            }
            .frame(width: 74, height: 74)
        }
        .buttonStyle(PadButtonStyle())
    }
}

/// 押下時に軽く縮むボタンスタイル。
private struct PadButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
