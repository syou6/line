import SwiftUI

/// アプリ全体の配色・見た目の定義。アイコンのシールド/キーホールと同系統の
/// ディープネイビー × ティールブルーで統一する。
enum Theme {
    static let accent = Color(red: 0.30, green: 0.62, blue: 0.90)
    static let accentDeep = Color(red: 0.18, green: 0.42, blue: 0.78)
    static let accentSoft = Color(red: 0.55, green: 0.78, blue: 0.98)

    static let bgTop = Color(red: 0.08, green: 0.13, blue: 0.24)
    static let bgMid = Color(red: 0.05, green: 0.08, blue: 0.17)
    static let bgBottom = Color(red: 0.02, green: 0.04, blue: 0.10)

    static let surface = Color.white.opacity(0.06)
    static let surfaceStroke = Color.white.opacity(0.10)

    static let accentGradient = LinearGradient(
        colors: [accentSoft, accent, accentDeep],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

/// ブランドの背景（縦グラデ + 上部のアクセントグロー）。
struct BrandBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.bgTop, Theme.bgMid, Theme.bgBottom],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(
                colors: [Theme.accent.opacity(0.28), .clear],
                center: .top, startRadius: 0, endRadius: 420
            )
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// ブランド背景を敷く。
    func brandBackground() -> some View {
        background(BrandBackground())
    }

    /// カード風の面。リスト行や情報ブロックに使う。
    func card(padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.surfaceStroke, lineWidth: 1)
            )
    }
}
