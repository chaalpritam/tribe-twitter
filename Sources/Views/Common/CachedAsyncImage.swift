import SwiftUI
import UIKit

/// In-memory decoded-image cache shared across every AvatarView /
/// embed image render in the app. SwiftUI's stock AsyncImage refires
/// a download + decode every time a row scrolls back into view; for
/// a feed of 50 tweets that means 50 re-decodes when you scroll up
/// and back down. NSCache holds the already-decoded UIImage so the
/// second render is a dictionary lookup.
///
/// URLSession's HTTP layer still does its own disk caching via
/// URLCache.shared (sized up at app start), so a fresh launch hits
/// disk instead of the network when the avatar hasn't changed.
final class ImageCache {
    static let shared = ImageCache()

    private let cache: NSCache<NSURL, UIImage> = {
        let c = NSCache<NSURL, UIImage>()
        c.totalCostLimit = 64 * 1024 * 1024 // ~64 MB of decoded pixels
        c.countLimit = 512
        return c
    }()

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func store(_ image: UIImage, for url: URL) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        cache.setObject(image, forKey: url as NSURL, cost: cost)
    }

    /// Configure the process-wide URLCache that URLSession.shared
    /// consults for HTTP-layer caching. Call once at app launch.
    static func configureURLCache() {
        URLCache.shared = URLCache(
            memoryCapacity: 16 * 1024 * 1024,   // 16 MB RAM
            diskCapacity: 256 * 1024 * 1024,    // 256 MB on disk
            directory: nil
        )
    }
}

/// Drop-in replacement for AsyncImage that consults `ImageCache`
/// before hitting the network and stores the decoded UIImage on
/// success. Re-renders synchronously from cache when the URL has
/// already been seen, so scrolled-back-in rows don't flash a
/// placeholder.
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    @State private var loaded: UIImage?
    @State private var failed = false

    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
        // Populate from cache synchronously so the first render is
        // already a hit when scrolling back into a previously loaded
        // row, avoiding a one-frame placeholder flash.
        if let url, let cached = ImageCache.shared.image(for: url) {
            self._loaded = State(initialValue: cached)
        }
    }

    var body: some View {
        Group {
            if let img = loaded {
                content(Image(uiImage: img))
            } else {
                placeholder()
            }
        }
        .task(id: url) { await load() }
    }

    @MainActor
    private func load() async {
        guard let url else {
            loaded = nil
            failed = false
            return
        }
        if let cached = ImageCache.shared.image(for: url) {
            loaded = cached
            failed = false
            return
        }
        failed = false
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                ImageCache.shared.store(image, for: url)
                loaded = image
            } else {
                failed = true
            }
        } catch {
            failed = true
        }
    }
}
