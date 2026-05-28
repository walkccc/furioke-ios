import SwiftUI

/// Ambient, blurred album-art wash that sits behind the NowPlaying surface so the
/// album is *present* without competing with the lyrics. A scrim layered over the
/// blur keeps foreground lyric text legible over high-contrast art in both light
/// and dark appearance — the scrim is built from `systemBackground`, so it adapts
/// automatically.
struct ArtworkBackdrop: View {
  let url: URL?
  /// `.glassEffect()` falls back to opaque material on its own under Reduce
  /// Transparency, but this wash is a hand-rolled translucent blur the system
  /// fallback never sees — so it's suppressed explicitly here, leaving the
  /// opaque `systemBackground` for maximum lyric legibility.
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  var body: some View {
    ZStack {
      Color(.systemBackground)

      if let url, !reduceTransparency {
        // The image must be told to fill the surface — `scaledToFill` alone
        // sizes to the image's intrinsic bounds, so without an expanding frame
        // the wash collapses and never shows.
        CachedArtworkImage(url: url) { image in
          image.resizable().scaledToFill()
        } placeholder: {
          Color.clear
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .blur(radius: 60)
        .opacity(0.6)

        // Legibility scrim: a touch heavier at top and bottom where the glass
        // header and control bar sit, lighter through the lyric band.
        LinearGradient(
          colors: [
            Color(.systemBackground).opacity(0.55),
            Color(.systemBackground).opacity(0.25),
            Color(.systemBackground).opacity(0.6),
          ],
          startPoint: .top,
          endPoint: .bottom
        )
      }
    }
    .ignoresSafeArea()
    .animation(Motion.ease, value: url)
    .accessibilityHidden(true)
  }
}
