import AppKit
import SwiftUI

/// Loads and caches game artwork once per key, so switching tabs never
/// re-fetches or flickers a placeholder. Candidates are tried in order:
/// older Steam apps often have only a wide header image, and some have no
/// art of their own at all.
@MainActor
final class ArtworkStore: ObservableObject {
    static let shared = ArtworkStore()

    @Published private(set) var revision = 0
    private var images: [String: NSImage] = [:]
    private var failed: Set<String> = []
    private var inFlight: Set<String> = []

    private init() {}

    func image(forKey key: String) -> NSImage? {
        images[key]
    }

    func load(key: String, candidates: [URL]) {
        guard images[key] == nil,
              !failed.contains(key),
              !inFlight.contains(key),
              !candidates.isEmpty
        else { return }
        inFlight.insert(key)

        Task { [weak self] in
            for url in candidates {
                // A player-supplied file always wins over the CDN.
                if url.isFileURL {
                    guard let image = NSImage(contentsOf: url) else { continue }
                    await self?.store(image, forKey: key)
                    return
                }
                guard let (data, response) = try? await URLSession.shared.data(from: url),
                      let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode),
                      let image = NSImage(data: data)
                else { continue }
                await self?.store(image, forKey: key)
                return
            }
            await self?.markFailed(key)
        }
    }

    private func store(_ image: NSImage, forKey key: String) {
        images[key] = image
        inFlight.remove(key)
        revision &+= 1
    }

    private func markFailed(_ key: String) {
        inFlight.remove(key)
        failed.insert(key)
        revision &+= 1
    }
}
