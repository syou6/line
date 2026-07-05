# プライベートメモ (PrivacyVault)

端末内で完結する、暗号化プライバシー保管アプリ（iOS / SwiftUI）。
メモをローカルで暗号化し、PIN と生体認証（Face ID / Touch ID）で保護します。
クラウド送信・アカウント登録・トラッキングは一切ありません。

## 主な機能

- **PINロック** — 6桁PINで解錠。PIN・平文はどこにも保存しません。
- **端末内暗号化** — メモは AES-GCM で暗号化し、鍵は PIN から PBKDF2 (HMAC-SHA256, 20万回) で導出。
- **生体認証** — Face ID / Touch ID で解錠（有効化時、鍵は生体認証付き Keychain に格納）。
- **自動施錠** — アプリがバックグラウンドに回ると自動でロック。
- **おとりPIN（デュレス保護）** — 本来のPINとは別のPINで、切り離された空の保管庫を開く。
  PINの開示を強要された場合などに本来の内容を守るための、一般的なセキュリティ機能です。
- **緊急ワイプ** — 全保管庫・鍵をワンタップで完全削除。

## セキュリティ設計

| 保存物 | 保存先 | 保護 |
|---|---|---|
| PBKDF2ソルト / 検証トークン | Keychain | `WhenUnlockedThisDeviceOnly`、端末外に出ない |
| 生体認証用の鍵 | Keychain | `.biometryCurrentSet` + `WhenPasscodeSet` |
| メモ本体（暗号文） | App Support 内ファイル | AES-GCM + `completeFileProtection` |
| PIN / メモ平文 | **保存しない** | — |

- PINの照合は「検証トークンを復号できるか」で判定するため、PINやそのハッシュを保持しません。
- primary / decoy それぞれ独立したソルト・鍵・暗号文を持ち、ストレージ上は区別されません。

## ビルド方法

Xcode プロジェクトは [XcodeGen](https://github.com/yonaskolb/XcodeGen) で生成します。

```bash
brew install xcodegen      # 未導入なら
xcodegen generate          # project.yml から PrivacyVault.xcodeproj を生成
open PrivacyVault.xcodeproj # Xcode で開く
```

Xcode で:

1. `PrivacyVault` ターゲットの **Signing & Capabilities** で自分の Team を選択（Bundle ID は必要に応じて変更）。
2. 実機を選んで Run（生体認証はシミュレータでは限定的。Features > Face ID で疑似操作可）。

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
  App/        アプリ入口・状態管理 (AppState, RootView)
  Security/   暗号・Keychain・生体認証
  Storage/    保管庫の永続化 (VaultManager, FileStore)
  Models/     データモデル
  Views/      画面 (ロック / 一覧 / 編集 / 設定)
  Resources/  Assets, 生成Info.plist
```
