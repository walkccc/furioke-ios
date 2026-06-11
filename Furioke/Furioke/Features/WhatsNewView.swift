import SwiftUI

/// One app release and its user-facing highlights. `version` is a verbatim
/// version string (never localized); each `items` entry is a localization key,
/// so the bullet copy translates via the string catalog.
struct ReleaseNote: Identifiable {
  var id: String {
    version
  }

  let version: String
  let items: [LocalizedStringKey]

  /// Newest first — the order they're rendered in `WhatsNewView`.
  static let all: [ReleaseNote] = [
    ReleaseNote(version: "1.0.2", items: [
      "Improved UI",
    ]),
    ReleaseNote(version: "1.0.1", items: [
      "Improved UI",
    ]),
    ReleaseNote(version: "1.0", items: [
      "Initial release",
    ]),
  ]
}

/// A "What's New" sheet: the release history rendered as a scroll of glass
/// cards, newest at the top. Presented from Settings (tapping the version line)
/// and dismissed with a trailing "Done" button.
///
/// Each release is a floating liquid-glass card matching the Settings idiom —
/// see-through `.clear` glass with a hairline top-lit edge — falling back to the
/// opaque `contentSurface` material under Reduce Transparency so the copy stays
/// legible.
struct WhatsNewView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: Spacing.l) {
          ForEach(ReleaseNote.all) { release in
            releaseCard(release)
          }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.xl)
      }
      .background(Color(.systemGroupedBackground).ignoresSafeArea())
      .navigationTitle("What's New")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
  }

  /// One release: the version as a bold heading over a dash-led list of its
  /// highlights, floated as a glass card.
  private func releaseCard(_ release: ReleaseNote) -> some View {
    let shape = RoundedRectangle(cornerRadius: Radii.xl, style: .continuous)
    let content = VStack(alignment: .leading, spacing: Spacing.m) {
      // Verbatim: the version string is a number, not a localization key.
      Text(verbatim: release.version)
        .font(Typography.sectionTitle)

      VStack(alignment: .leading, spacing: Spacing.s) {
        ForEach(release.items.indices, id: \.self) { index in
          HStack(alignment: .top, spacing: Spacing.s) {
            Text(verbatim: "–")
              .foregroundStyle(.secondary)
            Text(release.items[index])
          }
          .font(Typography.body)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(Spacing.l)

    return Group {
      if reduceTransparency {
        content.background(OpaqueMaterial.contentSurface.color, in: shape)
      } else {
        content
          .glassEffect(.clear, in: shape)
          .overlay(shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
      }
    }
  }
}

#Preview {
  WhatsNewView()
}
