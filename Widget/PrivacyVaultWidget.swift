import WidgetKit
import SwiftUI

// MARK: - タイムライン

struct NoteCountEntry: TimelineEntry {
    let date: Date
    let count: Int
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> NoteCountEntry {
        NoteCountEntry(date: Date(), count: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (NoteCountEntry) -> Void) {
        completion(NoteCountEntry(date: Date(), count: AppGroup.readNoteCount()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NoteCountEntry>) -> Void) {
        let entry = NoteCountEntry(date: Date(), count: AppGroup.readNoteCount())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3600))))
    }
}

// MARK: - 配色（本体アプリと同系統。ウィジェットは独立ターゲットのため自前定義）

private enum WidgetTheme {
    static let accent = Color(red: 0.30, green: 0.62, blue: 0.90)
    static let accentSoft = Color(red: 0.55, green: 0.78, blue: 0.98)
    static let bgTop = Color(red: 0.08, green: 0.13, blue: 0.24)
    static let bgBottom = Color(red: 0.02, green: 0.04, blue: 0.10)
    static let gradient = LinearGradient(colors: [bgTop, bgBottom], startPoint: .top, endPoint: .bottom)
}

// MARK: - ビュー

struct PrivacyVaultWidgetEntryView: View {
    var entry: Provider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "lock.shield.fill")
                    .font(.title3)
                    .foregroundStyle(WidgetTheme.accentSoft)
                Spacer()
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            }
            Spacer(minLength: 0)
            Text("\(entry.count)")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("件のメモ")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
            Text("タップして解錠")
                .font(.caption2)
                .foregroundStyle(WidgetTheme.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetBackground(WidgetTheme.gradient)
    }
}

private extension View {
    /// iOS16/17 両対応のウィジェット背景。
    @ViewBuilder
    func widgetBackground(_ bg: some View) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            containerBackground(for: .widget) { bg }
        } else {
            padding().background(bg)
        }
    }
}

// MARK: - 宣言

struct PrivacyVaultWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PrivacyVaultWidget", provider: Provider()) { entry in
            PrivacyVaultWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("プライベートメモ")
        .description("メモの件数を表示します。内容はアプリを解錠すると見られます。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct PrivacyVaultWidgetBundle: WidgetBundle {
    var body: some Widget {
        PrivacyVaultWidget()
    }
}
