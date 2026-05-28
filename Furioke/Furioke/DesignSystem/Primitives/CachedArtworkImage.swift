import SwiftUI
import UIKit

/// Process-wide decoded-image cache for album art.
///
/// `AsyncImage` keeps no cache, so it restarts from its placeholder phase every
/// time SwiftUI reconstructs the view (a tab switch re-evaluates `AppShell.body`,
/// which re-invokes the NowPlaying cover closure and rebuilds the backdrop). That
/// restart is what makes the blurred artwork wash flash on/off. A synchronous
/// cache hit lets a rebuilt view re-show the same image immediately instead.
@MainActor
enum ArtworkImageCache {
  private static let cache: NSCache<NSURL, UIImage> = {
    let cache = NSCache<NSURL, UIImage>()
    cache.countLimit = 64
    return cache
  }()

  static func image(for url: URL) -> UIImage? {
    cache.object(forKey: url as NSURL)
  }

  static func store(_ image: UIImage, for url: URL) {
    cache.setObject(image, forKey: url as NSURL)
  }
}

/// Drop-in replacement for `AsyncImage(url:content:placeholder:)` that survives
/// view-graph rebuilds. On a cache hit the image is resolved during `body`
/// evaluation, so the view never drops to its placeholder — no flash on tab
/// switch. A genuinely new URL still loads asynchronously behind the placeholder.
struct CachedArtworkImage<Content: View, Placeholder: View>: View {
  let url: URL?
  @ViewBuilder var content: (Image) -> Content
  @ViewBuilder var placeholder: () -> Placeholder

  @State private var loaded: UIImage?

  init(
    url: URL?,
    @ViewBuilder content: @escaping (Image) -> Content,
    @ViewBuilder placeholder: @escaping () -> Placeholder
  ) {
    self.url = url
    self.content = content
    self.placeholder = placeholder
  }

  var body: some View {
    Group {
      if let image = resolved {
        content(Image(uiImage: image))
      } else {
        placeholder()
      }
    }
    .task(id: url) { await load() }
  }

  /// Prefer freshly-loaded state, then fall back to the cache so a rebuilt view
  /// (fresh `@State`) still shows a previously-loaded image without a round trip.
  private var resolved: UIImage? {
    if let loaded { return loaded }
    if let url, let cached = ArtworkImageCache.image(for: url) { return cached }
    return nil
  }

  private func load() async {
    guard let url else {
      loaded = nil
      return
    }
    if let cached = ArtworkImageCache.image(for: url) {
      loaded = cached
      return
    }
    do {
      let (data, _) = try await URLSession.shared.data(from: url)
      guard let image = UIImage(data: data) else { return }
      ArtworkImageCache.store(image, for: url)
      loaded = image
    } catch {
      // Leave the placeholder showing; a later rebuild retries via `.task`.
    }
  }
}
