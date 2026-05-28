import SwiftUI

// Inner body of `NowPlayingSheet`: header chip, artwork, source chip, lyric
// column, scrubber, transport row. Section 9 replaces these display
// parameters with `NowPlayingState` bindings; for now the chrome has a stable
// shape that the feature wiring can drive.

struct NowPlayingContent: View {
  let title: String
  let artist: String
  let artworkURL: URL?
  let sourceLabel: String?
  let isPlaying: Bool
  let positionMs: Int
  let durationMs: Int
  let onPrev: () -> Void
  let onPlayPause: () -> Void
  let onNext: () -> Void
  let onSeek: (Int) -> Void

  var body: some View {
    ScrollView {
      VStack(spacing: Spacing.xl) {
        artwork
        if let sourceLabel {
          GlassCapsule {
            Text(sourceLabel)
          }
        }
        VStack(spacing: Spacing.xs) {
          Text(title)
            .font(Typography.pageTitle)
            .multilineTextAlignment(.center)
          Text(artist)
            .font(Typography.metadata)
            .foregroundStyle(.secondary)
        }
        // Lyric column placeholder — wired by section 9.
        Color.clear.frame(minHeight: 200)
        Scrubber(positionMs: positionMs, durationMs: durationMs, onSeek: onSeek)
          .padding(.horizontal, Spacing.l)
        HStack(spacing: Spacing.xl) {
          TransportButton(.previous, action: onPrev)
            .font(.system(size: 32))
          TransportButton(isPlaying ? .pause : .play, action: onPlayPause)
            .font(.system(size: 48))
          TransportButton(.next, action: onNext)
            .font(.system(size: 32))
        }
        .padding(.bottom, Spacing.l)
      }
      .padding(Spacing.l)
      .frame(maxWidth: .infinity)
    }
  }

  @ViewBuilder
  private var artwork: some View {
    let shape: RoundedRectangle = .init(cornerRadius: Radii.xl, style: .continuous)
    AsyncImage(url: artworkURL) { image in
      image.resizable().scaledToFill()
    } placeholder: {
      shape.fill(.quaternary)
    }
    .aspectRatio(1, contentMode: .fit)
    .frame(maxWidth: 320)
    .clipShape(shape)
  }
}
