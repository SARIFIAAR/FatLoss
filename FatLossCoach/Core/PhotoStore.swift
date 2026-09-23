import Foundation
import UIKit

/// Local on-device CACHE of progress (body) photos. THESE ARE SENSITIVE.
///
/// Cloud is the cross-device source of truth: each photo's JPEG lives in Firebase Storage at
/// `users/{uid}/photos/{id}.jpg` (metadata in a Firestore doc), synced by `PhotoSync`. This cache holds the
/// same JPEG bytes on-device for instant/offline display; it's a cache, not the record.
///
/// Hardening (mirrors the SurgiMD build-63 PHI-at-rest pattern; the local-data account-isolation marker
/// lives in `Keychain` / `Security.swift`):
///   • Cache files live under `Application Support/progress-photos/`, written with
///     `.completeFileProtectionUnlessOpen` so the bytes are encrypted at rest (readable only while the
///     device is unlocked / a handle is open).
///   • The directory is flagged `isExcludedFromBackup = true` so the cached photos are kept OUT of
///     iCloud/iTunes device backups (the cloud copy is the backup, scoped to the owner's uid).
///   • `wipeAll()` is called from `Store.resetLocalData()` (which `CloudSync.prepareForAccount` invokes when
///     a DIFFERENT Apple ID signs in), so a new account on the same device can't read the previous owner's
///     cached photos — the same isolation guarantee that protects the local data store. Cloud photos are
///     per-uid and rules-scoped owner-only, so cross-account reads are blocked server-side too.
enum PhotoStore {
    /// `Application Support/progress-photos`. Created (and hardened) lazily on first access.
    static var directory: URL {
        let dir = directoryURL
        ensureDirectory(dir)
        return dir
    }

    /// The dir URL WITHOUT the ensure/recreate side effect — used where we must not recreate before acting
    /// (e.g. `wipeAll` deletes then recreates; going through `directory` would recreate before the delete).
    private static var directoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("progress-photos", isDirectory: true)
    }

    /// Create the dir if missing and (re)apply the at-rest protections. Idempotent — safe to call often.
    private static func ensureDirectory(_ dir: URL) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true,
                                    attributes: [.protectionKey: FileProtectionType.completeUnlessOpen])
        }
        // Keep the whole cache dir out of iCloud/iTunes backups (body photos must not leave the device via backup).
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = dir
        try? mutable.setResourceValues(values)
    }

    static func url(for filename: String) -> URL {
        directory.appendingPathComponent(filename)
    }

    static func filename(for id: String) -> String { id + ".jpg" }

    // MARK: Compression

    /// Produce a lightly-compressed JPEG for upload to Firebase Storage: resize the long edge to ~2048 px at
    /// quality ~0.8 (good quality — Storage has no 1 MB limit). Re-encoding also strips the original's
    /// EXIF/location metadata. Returns nil only if encoding fails.
    static func compress(_ image: UIImage) -> Data? {
        downscaled(image, maxEdge: 2048).jpegData(compressionQuality: 0.8)
    }

    // MARK: Cache read/write

    /// Write already-encoded JPEG bytes into the local cache under `id`. Used for both a locally added photo
    /// and a photo downloaded from Firestore. Returns the cache filename, or nil on write failure.
    @discardableResult
    static func store(jpeg: Data, id: String) -> String? {
        let name = filename(for: id)
        let dest = url(for: name)
        do {
            try jpeg.write(to: dest, options: [.atomic, .completeFileProtectionUnlessOpen])
            return name
        } catch {
            print("PhotoStore.store failed: \(error)")
            return nil
        }
    }

    /// The cached JPEG bytes for an id, if present on this device.
    static func jpeg(for filename: String) -> Data? {
        guard !filename.isEmpty else { return nil }
        return try? Data(contentsOf: url(for: filename))
    }

    /// Load a cached image by filename, or nil if the bytes aren't on this device yet (not downloaded).
    static func load(_ filename: String) -> UIImage? {
        guard let data = jpeg(for: filename) else { return nil }
        return UIImage(data: data)
    }

    static func exists(_ filename: String) -> Bool {
        !filename.isEmpty && FileManager.default.fileExists(atPath: url(for: filename).path)
    }

    /// Delete one cached photo file (used when the user deletes a photo).
    static func delete(_ filename: String) {
        guard !filename.isEmpty else { return }
        try? FileManager.default.removeItem(at: url(for: filename))
    }

    /// Remove EVERY cached progress photo on this device. Called by `Store.resetLocalData()` on account
    /// switch so a different Apple ID on this device can't read the previous owner's cached body photos.
    static func wipeAll() {
        let dir = directoryURL                 // path only — do NOT recreate before deleting
        try? FileManager.default.removeItem(at: dir)
        // Recreate the (empty, hardened) dir so subsequent saves have a protected home.
        ensureDirectory(dir)
    }

    // MARK: Helpers

    private static func downscaled(_ image: UIImage, maxEdge: CGFloat) -> UIImage {
        let w = image.size.width, h = image.size.height
        let longEdge = max(w, h)
        guard longEdge > maxEdge, longEdge > 0 else { return image }
        let scale = maxEdge / longEdge
        let size = CGSize(width: w * scale, height: h * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}
