import Foundation
import Observation
import FirebaseFirestore
import FirebaseStorage

/// Cross-device sync for progress (body) photos.
///
///   • BYTES  → Firebase Storage at `users/{uid}/photos/{photoId}.jpg` (full-res-ish: long edge ~2048 px,
///              JPEG ~0.8). Storage is the cross-device source of truth.
///   • METADATA → a small Firestore doc `users/{uid}/photos/{photoId}`
///              { date, weightKg?, note?, ownerUid, createdAt, storagePath }. Kept OUT of the main
///              `users/{uid}` sync blob so that blob stays small.
///   • CACHE → `PhotoStore` keeps downloaded JPEGs on-device (file-protected, backup-excluded) for instant/
///              offline display; the cache is wiped on account switch by the existing `resetLocalData` path.
///
/// Privacy: Storage objects and Firestore docs are per-uid and rules-scoped owner-only with `ownerUid`
/// pinned on the metadata write (see storage.rules + firestore.rules). Upload on add; download-on-demand
/// (and cache) on other devices. Guests are local-only until sign-in, then `uploadPending()` pushes.
@Observable
final class PhotoSync {
    private weak var store: Store?
    private var listener: ListenerRegistration?
    private var uid: String?
    /// Photo ids already present remotely (from the live snapshot), so we only upload what's missing.
    private var remoteIDs = Set<String>()
    /// Ids currently downloading, so overlapping snapshots don't double-fetch.
    private var downloading = Set<String>()

    func attach(store: Store) { self.store = store }

    /// Start (or restart) syncing for a signed-in account. Called after account isolation has run.
    func start(uid: String) {
        guard uid != self.uid else { return }
        stop()
        self.uid = uid
        listener = metaCollection(uid).addSnapshotListener { [weak self] snap, _ in
            Task { @MainActor in self?.handleSnapshot(snap) }
        }
    }

    /// Stop syncing (sign-out / account switch). Does NOT touch the local cache — the isolation wipe owns that.
    func stop() {
        listener?.remove(); listener = nil
        uid = nil
        remoteIDs = []
        downloading = []
    }

    private func metaCollection(_ uid: String) -> CollectionReference {
        Firestore.firestore().collection("users").document(uid).collection("photos")
    }
    private func storageRef(_ uid: String, _ id: String) -> StorageReference {
        Storage.storage().reference(withPath: "users/\(uid)/photos/\(id).jpg")
    }

    // MARK: Incoming (remote metadata → local metadata + on-demand byte download)

    @MainActor
    private func handleSnapshot(_ snap: QuerySnapshot?) {
        guard let snap, let store, let uid else { return }
        var seen = Set<String>()
        for doc in snap.documents {
            let id = doc.documentID
            seen.insert(id)
            let data = doc.data()
            let filename = PhotoStore.filename(for: id)
            // Ensure the local metadata entry (so a photo added on another device appears here).
            if !store.data.progressPhotos.contains(where: { $0.id == id }) {
                let at = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                store.data.progressPhotos.append(ProgressPhoto(id: id, date: data["date"] as? String ?? "",
                                                               filename: filename, at: at,
                                                               weightKg: data["weightKg"] as? Double,
                                                               note: data["note"] as? String))
            }
            // Download the bytes if we don't have them cached yet (download-on-demand).
            if !PhotoStore.exists(filename), !downloading.contains(id) {
                download(uid: uid, id: id)
            }
        }
        remoteIDs = seen
        // A photo deleted on another device: drop its local metadata + cached bytes here too.
        for local in store.data.progressPhotos where !seen.contains(local.id) {
            PhotoStore.delete(local.filename)
            store.data.progressPhotos.removeAll { $0.id == local.id }
        }
        store.bumpPhotoCache()
        // Upload any local photos this account owns that aren't in the cloud yet (offline add / guest → sign-in).
        uploadPending()
    }

    @MainActor
    private func download(uid: String, id: String) {
        downloading.insert(id)
        // 20 MB ceiling is generous for a ~2048 px JPEG; guards against a pathological object.
        storageRef(uid, id).getData(maxSize: 20 * 1024 * 1024) { [weak self] data, _ in
            Task { @MainActor in
                guard let self else { return }
                self.downloading.remove(id)
                if let data { PhotoStore.store(jpeg: data, id: id); self.store?.bumpPhotoCache() }
            }
        }
    }

    // MARK: Outgoing (local → Storage bytes + Firestore metadata)

    /// Upload every local photo whose bytes are cached but which isn't present remotely yet.
    func uploadPending() {
        guard let store, let uid else { return }
        for photo in store.data.progressPhotos where !remoteIDs.contains(photo.id) {
            guard let jpeg = PhotoStore.jpeg(for: photo.filename) else { continue }   // no bytes to upload
            upload(uid: uid, photo: photo, jpeg: jpeg)
        }
    }

    /// Upload one photo: bytes to Storage, then metadata to Firestore (with `ownerUid` pinned + `storagePath`).
    private func upload(uid: String, photo: ProgressPhoto, jpeg: Data) {
        remoteIDs.insert(photo.id)                 // optimistic: don't re-queue before the write returns
        let path = "users/\(uid)/photos/\(photo.id).jpg"
        let meta = StorageMetadata(); meta.contentType = "image/jpeg"
        storageRef(uid, photo.id).putData(jpeg, metadata: meta) { [weak self] _, err in
            guard err == nil else { Task { @MainActor in self?.remoteIDs.remove(photo.id) }; return }
            var fields: [String: Any] = [
                "date": photo.date, "ownerUid": uid,
                "createdAt": Timestamp(date: photo.at), "storagePath": path,
            ]
            fields["weightKg"] = photo.weightKg
            fields["note"] = photo.note
            self?.metaCollection(uid).document(photo.id).setData(fields.compactMapValues { $0 })
        }
    }

    /// Delete a photo's cloud bytes + metadata doc (called alongside the local delete).
    func delete(id: String) {
        guard let uid else { return }
        remoteIDs.remove(id)
        metaCollection(uid).document(id).delete()
        storageRef(uid, id).delete { _ in }
    }
}
