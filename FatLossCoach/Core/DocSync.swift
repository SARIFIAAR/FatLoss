import Foundation
import Observation
import FirebaseFirestore
import FirebaseStorage

/// Cross-device sync for the personal health-document vault (E1-02). Mirrors `PhotoSync`:
///
///   • BYTES  → Firebase Storage `users/{uid}/documents/{id}.{ext}` (owner-only; the cross-device record).
///   • METADATA → a small Firestore doc `users/{uid}/documents/{id}`
///                { title, category, contentType, sizeBytes, ownerUid, createdAt, storagePath }.
///   • CACHE → `DocStore` keeps the bytes on-device (file-protected, backup-excluded) for instant/offline
///             viewing; wiped on account switch by `Store.resetLocalData`.
///
/// Privacy: Storage objects + Firestore docs are per-uid and rules-scoped owner-only, with `ownerUid`
/// pinned on the metadata write. HUMANS never reads or interprets the document contents.
@Observable
final class DocSync {
    private weak var store: Store?
    private var listener: ListenerRegistration?
    private var uid: String?
    private var remoteIDs = Set<String>()
    private var downloading = Set<String>()

    func attach(store: Store) { self.store = store }

    func start(uid: String) {
        guard uid != self.uid else { return }
        stop()
        self.uid = uid
        listener = metaCollection(uid).addSnapshotListener { [weak self] snap, _ in
            Task { @MainActor in self?.handleSnapshot(snap) }
        }
    }

    func stop() {
        listener?.remove(); listener = nil
        uid = nil
        remoteIDs = []
        downloading = []
    }

    private func metaCollection(_ uid: String) -> CollectionReference {
        Firestore.firestore().collection("users").document(uid).collection("documents")
    }
    private func storageRef(_ uid: String, _ id: String, _ ext: String) -> StorageReference {
        Storage.storage().reference(withPath: "users/\(uid)/documents/\(id).\(ext)")
    }

    // MARK: Incoming (remote metadata → local metadata + on-demand byte download)

    @MainActor
    private func handleSnapshot(_ snap: QuerySnapshot?) {
        guard let snap, let store, let uid else { return }
        var seen = Set<String>()
        for doc in snap.documents {
            let id = doc.documentID
            seen.insert(id)
            let d = doc.data()
            let contentType = d["contentType"] as? String ?? "application/pdf"
            let filename = DocStore.filename(for: id, contentType: contentType)
            if !store.data.documents.contains(where: { $0.id == id }) {
                let at = (d["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                let cat = HealthDoc.Category(rawValue: d["category"] as? String ?? "other") ?? .other
                store.data.documents.append(HealthDoc(
                    id: id, title: d["title"] as? String ?? "Document", filename: filename,
                    contentType: contentType, category: cat, at: at, sizeBytes: d["sizeBytes"] as? Int ?? 0))
            }
            if !DocStore.exists(filename), !downloading.contains(id) {
                download(uid: uid, id: id, contentType: contentType, filename: filename)
            }
        }
        remoteIDs = seen
        for local in store.data.documents where !seen.contains(local.id) {
            DocStore.delete(local.filename)
            store.data.documents.removeAll { $0.id == local.id }
        }
        store.bumpDocCache()
        uploadPending()
    }

    @MainActor
    private func download(uid: String, id: String, contentType: String, filename: String) {
        downloading.insert(id)
        let ext = DocStore.ext(for: contentType)
        storageRef(uid, id, ext).getData(maxSize: 30 * 1024 * 1024) { [weak self] data, _ in
            Task { @MainActor in
                guard let self else { return }
                self.downloading.remove(id)
                if let data { DocStore.store(data: data, filename: filename); self.store?.bumpDocCache() }
            }
        }
    }

    // MARK: Outgoing (local → Storage bytes + Firestore metadata)

    func uploadPending() {
        guard let store, let uid else { return }
        for doc in store.data.documents where !remoteIDs.contains(doc.id) {
            guard let bytes = DocStore.data(for: doc.filename) else { continue }
            upload(uid: uid, doc: doc, bytes: bytes)
        }
    }

    private func upload(uid: String, doc: HealthDoc, bytes: Data) {
        remoteIDs.insert(doc.id)
        let ext = DocStore.ext(for: doc.contentType)
        let path = "users/\(uid)/documents/\(doc.id).\(ext)"
        let meta = StorageMetadata(); meta.contentType = doc.contentType
        storageRef(uid, doc.id, ext).putData(bytes, metadata: meta) { [weak self] _, err in
            guard err == nil else { Task { @MainActor in self?.remoteIDs.remove(doc.id) }; return }
            let fields: [String: Any] = [
                "title": doc.title, "category": doc.category.rawValue, "contentType": doc.contentType,
                "sizeBytes": doc.sizeBytes, "ownerUid": uid,
                "createdAt": Timestamp(date: doc.at), "storagePath": path,
            ]
            self?.metaCollection(uid).document(doc.id).setData(fields)
        }
    }

    func delete(id: String, contentType: String) {
        guard let uid else { return }
        remoteIDs.remove(id)
        metaCollection(uid).document(id).delete()
        storageRef(uid, id, DocStore.ext(for: contentType)).delete { _ in }
    }
}
