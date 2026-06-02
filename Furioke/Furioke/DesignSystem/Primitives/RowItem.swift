import SwiftUI

// Library / search row: artwork + 2-line text + optional trailing slot.

struct RowItem<Trailing: View>: View {
  private let artworkURL: URL?
  private let title: String
  private let subtitle: String
  private let trailing: Trailing

  init(
    artworkURL: URL?,
    title: String,
    subtitle: String,
    @ViewBuilder trailing: () -> Trailing = { EmptyView() }
  ) {
    self.artworkURL = artworkURL
    self.title = title
    self.subtitle = subtitle
    self.trailing = trailing()
  }

  var body: some View {
    HStack(spacing: Spacing.m) {
      artwork
      VStack(alignment: .leading, spacing: Spacing.xs) {
        Text(title)
          .font(Typography.body)
          .lineLimit(1)
        Text(subtitle)
          .font(Typography.metadata)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer(minLength: 0)
      trailing
    }
    .padding(.vertical, Spacing.xs)
    .contentShape(Rectangle())
  }

  @ViewBuilder
  private var artwork: some View {
    let shape: RoundedRectangle = .init(cornerRadius: Radii.sm, style: .continuous)
    CachedArtworkImage(url: artworkURL) { image in
      image.resizable().scaledToFill()
    } placeholder: {
      shape.fill(.quaternary)
    }
    .frame(width: 56, height: 56)
    .clipShape(shape)
  }
}
