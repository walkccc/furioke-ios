import SwiftUI

/// The Save / Saved affordance on saved-song surfaces (Search result rows).
/// Presentational — it reflects `isSaved` and fires `action` on tap.
/// `.borderless` so it captures its own tap inside a row that is itself a Button,
/// and disabled once saved so it reads purely as a "Saved" badge.
struct SaveButton: View {
  let isSaved: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: isSaved ? "checkmark.circle.fill" : "plus.circle")
        .font(.system(size: 22))
        .foregroundStyle(isSaved ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(.borderless)
    .disabled(isSaved)
    .accessibilityLabel(isSaved ? "Saved to library" : "Save to library")
  }
}
