import SwiftUI

/// A single illustrated teaching card: a simple visual sketch over short, calm
/// copy. Teaching cards describe the app rather than driving the live UI, so
/// they render identically regardless of network, sign-in, provider, or
/// playback state. Built from the design tokens and SF Symbols — no screenshots
/// to maintain.
struct OnboardingTeachingCard<Sketch: View>: View {
  let title: LocalizedStringKey
  let message: LocalizedStringKey
  @ViewBuilder var sketch: () -> Sketch

  var body: some View {
    VStack(spacing: Spacing.xl) {
      sketch()
        .frame(maxWidth: .infinity)
        .frame(height: 168)
        .accessibilityHidden(true)
      VStack(spacing: Spacing.s) {
        Text(title)
          .font(Typography.sectionTitle)
          .multilineTextAlignment(.center)
        Text(message)
          .font(Typography.body)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .lineLimit(4, reservesSpace: true)
      }
    }
    .padding(.horizontal, Spacing.xl)
    .accessibilityElement(children: .combine)
  }
}

// MARK: - Shared sketch chrome

/// A soft accent-tinted rounded tile that hosts a sketch's glyphs, giving every
/// teaching card a consistent illustrative frame. Pure colour, so it stays
/// legible under Reduce Transparency.
struct OnboardingSketchTile<Content: View>: View {
  @ViewBuilder var content: () -> Content

  var body: some View {
    RoundedRectangle(cornerRadius: Radii.xxl, style: .continuous)
      .fill(Color("AccentColor").opacity(0.12))
      .overlay {
        RoundedRectangle(cornerRadius: Radii.xxl, style: .continuous)
          .strokeBorder(Color("AccentColor").opacity(0.18), lineWidth: 1)
      }
      .overlay { content() }
      .frame(maxWidth: 260)
  }
}

/// The default single-glyph sketch shared by most teaching cards.
struct OnboardingGlyphSketch: View {
  let systemName: String

  var body: some View {
    OnboardingSketchTile {
      Image(systemName: systemName)
        .font(.system(size: 64, weight: .regular))
        .foregroundStyle(Color("AccentColor"))
        .symbolRenderingMode(.hierarchical)
    }
  }
}

// MARK: - Bespoke sketches

/// Helpers card: the three lyric-helper toggles as the Now Playing toolbar shows
/// them — furigana on (the あ disc), with rōmaji (`textformat.alt`) and
/// translation (`globe`) available. Mirrors the real toolbar glyphs.
struct OnboardingHelpersSketch: View {
  var body: some View {
    OnboardingSketchTile {
      HStack(spacing: Spacing.s) {
        chip(active: true) {
          Text("あ")
            .font(.system(size: 22, weight: .bold, design: .rounded))
        }
        chip(active: false) {
          Image(systemName: "textformat.alt")
            .font(.system(size: 20, weight: .semibold))
        }
        chip(active: false) {
          Image(systemName: "translate")
            .font(.system(size: 20, weight: .semibold))
        }
      }
    }
  }

  private func chip(active: Bool, @ViewBuilder glyph: () -> some View) -> some View {
    glyph()
      .foregroundStyle(active ? Color.white : Color("AccentColor"))
      .frame(width: 52, height: 52)
      .background(
        RoundedRectangle(cornerRadius: Radii.md, style: .continuous)
          .fill(active ? Color("AccentColor") : Color("AccentColor").opacity(0.14))
      )
  }
}

/// Long-press card: a lyric word with a small saved-star badge, evoking the
/// press-to-save / override interaction.
struct OnboardingLongPressSketch: View {
  var body: some View {
    OnboardingSketchTile {
      VStack(spacing: Spacing.s) {
        Text("言葉")
          .font(.system(.largeTitle, design: .rounded, weight: .semibold))
          .padding(.horizontal, Spacing.l)
          .padding(.vertical, Spacing.s)
          .background(
            RoundedRectangle(cornerRadius: Radii.md, style: .continuous)
              .fill(Color("AccentColor").opacity(0.18))
          )
        Image(systemName: "hand.tap.fill")
          .font(.system(size: 22, weight: .semibold))
          .foregroundStyle(Color("AccentColor"))
      }
    }
  }
}

/// Tango card: the list ⇄ flashcards study-mode pairing.
struct OnboardingTangoSketch: View {
  var body: some View {
    OnboardingSketchTile {
      HStack(spacing: Spacing.l) {
        modeGlyph(symbol: "rectangle.on.rectangle.angled")
        Image(systemName: "arrow.left.arrow.right")
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(.secondary)
        modeGlyph(symbol: "ellipse")
      }
    }
  }

  private func modeGlyph(symbol: String) -> some View {
    Image(systemName: symbol)
      .font(.system(size: 34, weight: .regular))
      .foregroundStyle(Color("AccentColor"))
      .frame(width: 64, height: 64)
      .background(
        RoundedRectangle(cornerRadius: Radii.md, style: .continuous)
          .fill(Color("AccentColor").opacity(0.14))
      )
  }
}
