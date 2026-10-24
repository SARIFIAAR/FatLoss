import Foundation

/// Local on-device CACHE of personal health documents (E1-02 vault). SENSITIVE — same at-rest hardening
/// as `PhotoStore`: files live under `Application Support/health-docs/`, written with complete file
/// protection and excluded from iCloud/iTunes backups. Cloud (Firebase Storage
/// `users/{uid}/documents/{id}.{ext}`) is the cross-device source of truth; this holds the same bytes
/// on-device for instant/offline viewing. `wipeAll()` runs on account switch (`Store.resetLocalData`) so a
/// different Apple ID on this device can never read the previous owner's documents.
enum DocStore {
    static var directory: URL { let d = directoryURL; ensureDirectory(d); return d }

    private static var directoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("health-docs", isDirectory: true)
    }

    private static func ensureDirectory(_ dir: URL) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true,
                                    attributes: [.protectionKey: FileProtectionType.completeUnlessOpen])
        }
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var mutable = dir; try? mutable.setResourceValues(values)
    }

    static func url(for filename: String) -> URL { directory.appendingPathComponent(filename) }

    static func ext(for contentType: String) -> String {
        switch contentType {
        case "application/pdf": return "pdf"
        case "image/png":       return "png"
        default:                return "jpg"
        }
    }

    static func filename(for id: String, contentType: String) -> String {
        id + "." + ext(for: contentType)
    }

    @discardableResult
    static func store(data: Data, filename: String) -> Bool {
        do {
            try data.write(to: url(for: filename), options: [.atomic, .completeFileProtectionUnlessOpen])
            return true
        } catch {
            print("DocStore.store failed: \(error)")
            return false
        }
    }

    static func data(for filename: String) -> Data? {
        guard !filename.isEmpty else { return nil }
        return try? Data(contentsOf: url(for: filename))
    }

    static func exists(_ filename: String) -> Bool {
        !filename.isEmpty && FileManager.default.fileExists(atPath: url(for: filename).path)
    }

    static func delete(_ filename: String) {
        guard !filename.isEmpty else { return }
        try? FileManager.default.removeItem(at: url(for: filename))
    }

    /// Remove EVERY cached document on this device. Called by `Store.resetLocalData()` on account switch.
    static func wipeAll() {
        let dir = directoryURL
        try? FileManager.default.removeItem(at: dir)
        ensureDirectory(dir)
    }
}
