import UIKit
import UniformTypeIdentifiers

/// 他アプリからテキスト／URLを共有 → 受信箱へ封をして追加する。
/// 拡張はPIN鍵を持てないため、本体アプリの公開鍵で封をするだけ（開封は本体のみ）。
class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.05, green: 0.08, blue: 0.17, alpha: 1)
        handleShare()
    }

    private func handleShare() {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let providers = item.attachments, !providers.isEmpty else {
            return complete()
        }

        let group = DispatchGroup()
        var collected: [String] = []
        let lock = NSLock()

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { data, _ in
                    if let s = data as? String {
                        lock.lock(); collected.append(s); lock.unlock()
                    }
                    group.leave()
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { data, _ in
                    if let url = data as? URL {
                        lock.lock(); collected.append(url.absoluteString); lock.unlock()
                    }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            let text = collected.joined(separator: "\n")
            if !text.isEmpty {
                let draft = InboxCodec.makeDraft(from: text, now: Date())
                InboxStore.enqueue(draft)
            }
            self?.complete()
        }
    }

    private func complete() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
