import SwiftUI
import UIKit

/// Disk-backed image cache for remote program/recipe photos.
///
/// Why not plain `AsyncImage`: it re-downloads on every appearance (no persistent cache), which for a
/// grid of studio photos means repeated network hits and a flash of placeholder each time. This caches
/// the decoded bytes to Application Support keyed by a hash of the URL, so a photo downloads once and
/// then loads instantly offline. `URLCache.shared` (memory + disk) backs the live fetch as well.
///
/// Remote images are plain public URLs (no auth token) per the shared content schema.
actor ImageCache {
    static let shared = ImageCache()

    private let dir: URL
    private var memory: [String: UIImage] = [:]

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("image-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func key(_ url: URL) -> String {
        // Stable filename from the URL; avoids slashes/illegal chars without pulling in CryptoKit here.
        String(UInt64(bitPattern: Int64(url.absoluteString.hashValue)))
    }

    private func fileURL(_ url: URL) -> URL { dir.appendingPathComponent(key(url) + ".img") }

    func image(for url: URL) async -> UIImage? {
        let k = key(url)
        if let img = memory[k] { return img }
        // Disk cache (persists across launches / works offline).
        if let data = try? Data(contentsOf: fileURL(url)), let img = UIImage(data: data) {
            memory[k] = img
            return img
        }
        // Network fetch → persist to disk + memory.
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let img = UIImage(data: data) else { return nil }
            try? data.write(to: fileURL(url), options: .atomic)
            memory[k] = img
            return img
        } catch {
            return nil
        }
    }
}

/// A remote image that disk-caches and falls back to a bundled asset when the URL is absent or fails.
/// Used for the program banner and recipe photos. Keeps the existing fill-mode pattern
/// (`Color.clear.frame.overlay { image }.clipShape`) so it never overflows its frame.
struct CachedProgramImage: View {
    let urlString: String?
    let fallbackAsset: String
    var contentMode: ContentMode = .fill

    @State private var remote: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let remote {
                Image(uiImage: remote).resizable().aspectRatio(contentMode: contentMode)
            } else {
                // Bundled fallback — shown for the seed, while loading, and if the remote fetch fails.
                Image(fallbackAsset).resizable().aspectRatio(contentMode: contentMode)
            }
        }
        .task(id: urlString) { await load() }
    }

    private func load() async {
        remote = nil
        failed = false
        guard let urlString, let url = URL(string: urlString), url.scheme?.hasPrefix("http") == true else { return }
        if let img = await ImageCache.shared.image(for: url) {
            remote = img
        } else {
            failed = true   // keep the bundled fallback on screen
        }
    }
}
