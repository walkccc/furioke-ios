import SwiftUI

// `.glassEffect()` wrapper. The `role` parameter is typed `GlassRole`, so
// passing `Materials.contentSurface` fails to compile — glass is reserved for
// chrome with a refractable backdrop.

struct GlassChrome<Content: View>: View {
  private let role: GlassRole
  private let shape: AnyShape
  private let content: Content

  init(
    role: GlassRole,
    @ViewBuilder content: () -> Content
  ) {
    self.init(
      role: role,
      in: RoundedRectangle(cornerRadius: Radii.xl, style: .continuous),
      content: content
    )
  }

  init<S: Shape>(
    role: GlassRole,
    in shape: S,
    @ViewBuilder content: () -> Content
  ) {
    self.role = role
    self.shape = AnyShape(shape)
    self.content = content()
  }

  var body: some View {
    content.glassEffect(role.glass, in: shape)
  }
}
