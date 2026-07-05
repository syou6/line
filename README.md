# プライベートメモ (PrivacyVault)

端末内で完結する、暗号化プライバシー保管アプリ（iOS / SwiftUI）。
メモをローカルで暗号化し、PIN と生体認証（Face ID / Touch ID）で保護します。
クラウド送信・アカウント登録・トラッキングは一切ありません。

![screens](docs/mockup-lock.png)

## 主な機能

- **PINロック** — 6桁PINで解錠。PIN・平文はどこにも保存しません。
- **端末内暗号化** — メモは AES-GCM で暗号化し、鍵は PIN から PBKDF2 (HMAC-SHA256, 20万回) で導出。
- **生体認証** — Face ID / Touch ID で解錠（有効化時、鍵は生体認証付き Keychain に格納）。
- **タグ & 検索** — メモにタグを付与し、キーワード検索・タグでの絞り込みが可能。
- **iCloud同期（暗号化）** — 暗号文のまま CloudKit プライベートDBへ同期。同じPINの端末どうしで内容を共有。
- **自動施錠** — アプリがバックグラウンドに回ると自動でロック。
- **おとりPIN（デュレス保護）** — 本来のPINとは別のPINで、切り離された保管庫を開く。
  PINの開示を強要された場合などに本来の内容を守るための、一般的なセキュリティ機能です。
  おとり側には当たり障りのない初期メモが入っており、空で不自然に見えることを防ぎます。
- **緊急ワイプ** — 全保管庫・鍵（同期済みなら iCloud のレコードも）をワンタップで完全削除。

デザインは、アイコンのシールド/キーホールと同系統のディープネイビー × ティールブルーで統一しています
（`Sources/App/Theme.swift`）。

## セキュリティ設計

| 保存物 | 保存先 | 保護 |
|---|---|---|
| PBKDF2ソルト / 検証トークン | Keychain | `WhenUnlockedThisDeviceOnly`、端末外に出ない |
| 生体認証用の鍵 | Keychain | `.biometryCurrentSet` + `WhenPasscodeSet` |
| メモ本体（暗号文） | App Support 内ファイル | AES-GCM + `completeFileProtection` |
| PIN / メモ平文 | **保存しない** | — |

- PINの照合は「検証トークンを復号できるか」で判定するため、PINやそのハッシュを保持しません。
- primary / decoy それぞれ独立したソルト・鍵・暗号文を持ち、ストレージ上は区別されません。
- iCloud には **暗号文のみ** を送信します。鍵は端末外に出ないため、iCloud側では復号できません。

### iCloud同期について

- 種別（primary/decoy）ごとに1レコード（`VaultBlob`）を CloudKit プライベートDBへ upsert します。
- マージは **item単位の last-writer-wins**（`updatedAt` が新しい方を採用）。
- 既知の制約: 削除は「両端末がオンラインで同期される」まで、別端末の blob から復活し得ます
  （item単位のトゥームストーンは未実装）。実運用では削除後に各端末で一度同期してください。

## ビルド方法

Xcode プロジェクトは [XcodeGen](https://github.com/yonaskolb/XcodeGen) で生成します。

```bash
brew install xcodegen      # 未導入なら
xcodegen generate          # project.yml から PrivacyVault.xcodeproj を生成
open PrivacyVault.xcodeproj # Xcode で開く
```

Xcode で:

1. `PrivacyVault` ターゲットの **Signing & Capabilities** で自分の Team を選択（Bundle ID は必要に応じて変更）。
2. **iCloud（CloudKit）** を使う場合:
   - Capabilities に iCloud を追加し、CloudKit にチェック。
   - コンテナ `iCloud.<あなたのBundleID>` を作成し、`project.yml` / エンタイトルメントのコンテナIDを合わせる。
   - `VaultBlob` レコードtype（`blob`: Asset フィールド）は開発環境では初回保存時に自動作成されます。
     本番運用前に CloudKit Dashboard で Production スキーマへデプロイしてください。
3. 実機を選んで Run（生体認証はシミュレータでは限定的。Features > Face ID で疑似操作可）。

## App Store への申請メモ

- `NSFaceIDUsageDescription` は設定済み（`project.yml`）。
- `ITSAppUsesNonExemptEncryption = false`（標準の暗号のみ使用）を設定済み。用途に応じて輸出コンプライアンスの申告を確認してください。
- App Store 提出には 1024×1024 のアプリアイコンが必要です。`Assets.xcassets/AppIcon.appiconset` に画像を追加してください。

## 動作環境

- iOS 16.0 以上
- Swift 5 / SwiftUI

## ディレクトリ構成

```
Sources/
  App/        アプリ入口・状態管理・配色 (AppState, RootView, Theme)
  Security/   暗号・Keychain・生体認証
  Storage/    保管庫の永続化・iCloud同期 (VaultManager, FileStore, CloudSyncService)
  Models/     データモデル・おとり初期メモ
  Views/      画面 (ロック / 一覧 / 編集 / タグ / 設定)
  Resources/  Assets(アイコン), 生成Info.plist/entitlements
```
