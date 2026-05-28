import SwiftUI

// Pill chip wearing glass (provider chip, device chip, source label).

struct GlassCapsule<Content: View>: View {
  private let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    content
      .font(Typography.metadata)
      .padding(.horizontal, Spacing.m)
      .padding(.vertical, Spacing.xs)
      .glassEffect(Materials.capsuleTier.glass, in: Capsule())
  }
}
