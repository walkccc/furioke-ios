import SwiftUI

// Collapsed-state row hosted above the tab bar via `tabViewBottomAccessory`.
// Section 6 wires this from `MusicState`; for now it takes the minimum display
// data + action callbacks so the chrome can render without feature plumbing.
// The hosting accessory provides the chromeGlass backdrop, so this view does
// not apply its own glass.

struct MiniPlayer: View {
  let title: String
  let artist: String
  let artworkURL: URL?
  let isPlaying: Bool
  let onTap: () -> Void
  let onPlayPause: () -> Void

  var body: some View {
    Button(action: onTap) {
      HStack(spacing: Spacing.s) {
        artwork
        VStack(alignment: .leading, spacing: 2) {
          Text(title).font(Typography.body).lineLimit(1)
          Text(artist).font(Typography.metadata).foregroundStyle(.secondary).lineLimit(1)
        }
        Spacer(minLength: 0)
        TransportButton(isPlaying ? .pause : .play, action: onPlayPause)
          .font(.title2)
      }
      .padding(.horizontal, Spacing.m)
      .padding(.vertical, Spacing.s)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Now playing \(title) by \(artist). Tap to expand.")
  }

  @ViewBuilder
  private var artwork: some View {
    let shape: RoundedRectangle = .init(cornerRadius: Radii.sm, style: .continuous)
    AsyncImage(url: artworkURL) { image in
      image.resizable().scaledToFill()
    } placeholder: {
      shape.fill(.quaternary)
    }
    .frame(width: 36, height: 36)
    .clipShape(shape)
  }
}
