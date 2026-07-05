import Foundation

/// おとり保管庫の初期メモ。空だと不自然なため、当たり障りのない内容を数件入れておく。
enum DecoySeed {
    static func items() -> [VaultItem] {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        func at(_ days: Int) -> Date { base.addingTimeInterval(Double(days) * 86_400) }

        return [
            VaultItem(
                title: "買い物リスト",
                body: "牛乳、卵、パン、洗剤、電池（単3）\nコーヒー豆も切らしそう",
                tags: ["生活"],
                updatedAt: at(1)
            ),
            VaultItem(
                title: "読みたい本",
                body: "・積読を減らす\n・図書館で借りるリスト\n・小説とビジネス書を交互に",
                tags: ["メモ"],
                updatedAt: at(2)
            ),
            VaultItem(
                title: "旅行のアイデア",
                body: "次の連休はどこか近場に。温泉か、海の見える宿。予算は後で調整。",
                tags: ["旅行"],
                updatedAt: at(3)
            ),
            VaultItem(
                title: "パスワードのヒント",
                body: "Wi-Fiのパスは玄関のメモ。ルーター再起動は月1くらいで。",
                tags: ["メモ"],
                updatedAt: at(4)
            ),
            VaultItem(
                title: "やることリスト",
                body: "・クリーニング取りに行く\n・電球の買い替え\n・写真のバックアップ整理",
                tags: ["ToDo"],
                updatedAt: at(5)
            ),
        ]
    }
}
