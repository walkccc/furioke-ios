import SwiftUI

// One-time coach mark pointing at the mini-player. `AppShell` gates visibility
// on `@AppStorage` and the presence of a loaded track; this view is just the
// glass callout + its downward pointer, anchored above the tab bar.
//
// Glass is correct here — it is chrome floating over scrolling content, so it
// uses the capsule tier per the chrome-vs-content split.

struct MiniPlayerHint: View {
  let onClose: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: Spacing.s) {
        Image(systemName: "hand.tap")
          .font(.system(size: 15, weight: .semibold))
        Text("Tap the player to open lyrics")
          .font(Typography.metadata)
          .fixedSize(horizontal: false, vertical: true)
        Button(action: onClose) {
          Image(systemName: "xmark")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss hint")
      }
      .padding(.leading, Spacing.m)
      .padding(.trailing, Spacing.xs)
      .padding(.vertical, Spacing.s)
      .glassEffect(Materials.capsuleTier.glass, in: Capsule())

      // Downward pointer toward the mini-player below.
      Image(systemName: "arrowtriangle.down.fill")
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .offset(y: -2)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Tap the player to open lyrics")
    .transition(.opacity.combined(with: .move(edge: .bottom)))
  }
}
