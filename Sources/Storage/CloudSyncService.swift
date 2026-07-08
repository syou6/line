import Foundation
import CloudKit

/// CloudKit プライベートDBを使った暗号化同期。
///
/// 同期するのは「PIN由来の鍵で AES-GCM 暗号化済みの blob」のみ。
/// 鍵もPINも平文メモもクラウドには一切送られない（サーバは暗号文しか見えない）。
/// 保管庫の種別ごとに1レコードを upsert する。
actor CloudSyncService {
    static let shared = CloudSyncService()

    private let container = CKContainer(identifier: "iCloud.com.example.privacyvault")
    private var db: CKDatabase { container.privateCloudDatabase }
    private let recordType = "VaultBlob"
    private let field = "blob"

    /// ユーザーがiCloud同期を有効にしているか（UserDefaults）。
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "iCloudSyncEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "iCloudSyncEnabled") }
    }

    private func recordID(_ kind: VaultKind) -> CKRecord.ID {
        CKRecord.ID(recordName: "vault-\(kind.rawValue)")
    }

    /// サインイン済みでCloudKitが使えるか。
    func accountAvailable() async -> Bool {
        (try? await container.accountStatus()) == .available
    }

    /// リモートの暗号文を取得。レコードが無ければ nil。
    func fetchBlob(kind: VaultKind) async throws -> Data? {
        do {
            let record = try await db.record(for: recordID(kind))
            guard let asset = record[field] as? CKAsset, let url = asset.fileURL else { return nil }
            return try Data(contentsOf: url)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    /// リモートへ暗号文を upsert。
    func uploadBlob(_ data: Data, kind: VaultKind) async throws {
        let id = recordID(kind)
        let record = (try? await db.record(for: id)) ?? CKRecord(recordType: recordType, recordID: id)

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: tmp)
        record[field] = CKAsset(fileURL: tmp)
        _ = try await db.save(record)
        try? FileManager.default.removeItem(at: tmp)
    }

    /// リモートのレコードを削除（保管庫削除・ワイプ時）。
    func deleteBlob(kind: VaultKind) async {
        _ = try? await db.deleteRecord(withID: recordID(kind))
    }
}
