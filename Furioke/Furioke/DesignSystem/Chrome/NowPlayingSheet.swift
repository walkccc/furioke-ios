import SwiftUI

// Full-height container with a glass header. The sheet *presentation* itself
// is owned by `AppShell` (section 6 wires `.sheet` / `.fullScreenCover` / the
// custom partial sheet); this view is only the inner layout.

struct NowPlayingSheet<Content: View>: View {
  let onCollapse: () -> Void
  @ViewBuilder var content: () -> Content

  var body: some View {
    VStack(spacing: 0) {
      header
      content()
    }
  }

  private var header: some View {
    HStack(spacing: 0) {
      Button(action: onCollapse) {
        Image(systemName: "chevron.down")
          .font(.system(size: 16, weight: .semibold))
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Collapse player")
      Spacer(minLength: 0)
      Text("Now Playing")
        .font(Typography.metadata)
        .foregroundStyle(.secondary)
      Spacer(minLength: 0)
      Color.clear.frame(width: 44, height: 44)
    }
    .padding(.horizontal, Spacing.s)
    .frame(maxWidth: .infinity)
    .glassEffect(Materials.chromeGlass.glass, in: Rectangle())
  }
}
