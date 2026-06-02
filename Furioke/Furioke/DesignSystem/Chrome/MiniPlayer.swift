import SwiftUI

// Collapsed-state row hosted above the tab bar via `tabViewBottomAccessory`.
// The hosting accessory provides the chromeGlass backdrop, so this view does
// not apply its own glass.
//
// `AppShell` attaches a `.matchedTransitionSource` to this row, so the whole
// platter zooms up into the NowPlaying `.fullScreenCover` — the native
// zoom transition owns the morph; there are no per-element matched-geometry ids.
//
// Tap or drag-up both expand — `onExpand` is invoked for either gesture so the
// drag-up affordance shares the tap's expansion path.

struct MiniPlayer: View {
  let title: String
  let artist: String
  let artworkURL: URL?
  let isPlaying: Bool
  let onExpand: () -> Void
  let onPlayPause: () -> Void

  var body: some View {
    Button(action: onExpand) {
      HStack(spacing: Spacing.s) {
        artwork
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(Typography.body)
            .lineLimit(1)
          Text(artist)
            .font(Typography.metadata)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        Spacer(minLength: 0)
        TransportButton(isPlaying ? .pause : .play, action: onPlayPause)
          .font(.title3)
      }
      .padding(.horizontal, Spacing.l)
      .padding(.vertical, Spacing.s)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    // Drag-up expands too; runs alongside the button's tap so both work.
    .simultaneousGesture(
      DragGesture(minimumDistance: 12)
        .onEnded { value in
          if value.translation.height < -24 { onExpand() }
        }
    )
    .accessibilityLabel("Now playing \(title) by \(artist). Tap to expand.")
  }

  @ViewBuilder
  private var artwork: some View {
    let shape: RoundedRectangle = .init(cornerRadius: Radii.sm, style: .continuous)
    CachedArtworkImage(url: artworkURL) { image in
      image.resizable().scaledToFill()
    } placeholder: {
      shape.fill(.quaternary)
    }
    .frame(width: 36, height: 36)
    .clipShape(shape)
  }
}
