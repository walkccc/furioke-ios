import SwiftUI

// Opaque content card. The `material` parameter is typed `OpaqueMaterial`, so
// passing `Materials.chromeGlass` fails to compile — Surface is reserved for
// content that needs maximum legibility (forms, dialogs, editors).

struct Surface<Content: View>: View {
  private let material: OpaqueMaterial
  private let cornerRadius: CGFloat
  private let content: Content

  init(
    material: OpaqueMaterial,
    cornerRadius: CGFloat = Radii.lg,
    @ViewBuilder content: () -> Content
  ) {
    self.material = material
    self.cornerRadius = cornerRadius
    self.content = content()
  }

  var body: some View {
    content
      .background(
        material.color,
        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
      )
  }
}
