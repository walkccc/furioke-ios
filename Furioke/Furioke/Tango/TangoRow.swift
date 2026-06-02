import SwiftUI

/// One browse-list row, standalone and self-contained the way `FlashcardView` is so
/// the two stay easy to reason about side by side. Laid out the same for every card:
/// the word as ruby with its active-language meaning tucked directly beneath (when
/// translations are shown); then, when
/// the source line is shown, the captured lyric line beneath with a leading play
/// button, the line's translation, and — when the citation is shown — the song
/// attribution. The word shares `FlashcardStyle` with the study card, so its strokes
/// read at the same thickness in both places.
///
/// Unlike the study card — whose surface is deliberately **opaque** so deck cards
/// can't bleed through during the 3D flip — the browse row wears Liquid **glass**
/// (`GlassChrome`), floating each card over the list's artwork backdrop. This is an
/// intentional exception to the design system's chrome-vs-content split: the row
/// has no overlapping neighbour to bleed through, and the list (`TangoListView`)
/// hides its own background and lays the artwork wash behind it so the glass has a
/// rich backdrop to refract rather than reading as flat translucency.
///
/// A missing translation shows a tap-to-translate affordance (the same one the study
/// back face uses); the gloss is fetched — and the out-of-quota notice raised on a
/// spent daily limit — only on that explicit tap, never on appearance.
struct TangoRow: View {
  let card: Flashcard
  let target: String
  let showSource: Bool
  let showTranslation: Bool
  let showCitation: Bool

  private var meaning: String? {
    glossFor(card.meaning, target)
  }

  private var lineTranslation: String? {
    glossFor(card.sourceLineTranslation, target)
  }

  var body: some View {
    GlassChrome(role: Materials.chromeGlass) {
      VStack(alignment: .leading, spacing: Spacing.s) {
        header
        if showSource, let line = card.sourceLine {
          citation(line)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(Spacing.l)
    }
  }

  /// The word group: the word as ruby and — when translations are shown — its
  /// meaning directly beneath, so the word and its meaning read as one vertical
  /// unit rather than two detached columns.
  private var header: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
        RubyText(
          tokens: FuriganaAnnotator.align(surface: card.surface, reading: card.reading),
          showFurigana: true,
          surfaceFont: FlashcardStyle.rowWord,
          furiganaFont: FlashcardStyle.rowFurigana
        )
        Spacer(minLength: 0)
      }
      meaningView
    }
  }

  /// The word's meaning beneath it, shown only when translations are on: the gloss
  /// if present, a redacted placeholder while a fetch is in flight, or — when
  /// neither — the same tap-to-translate affordance the study back face uses, so a
  /// missing gloss is fetched only on an explicit tap (never on appearance, so the
  /// out-of-quota toast can't fire from merely browsing). Leading-aligned so it
  /// tucks directly under the word.
  @ViewBuilder
  private var meaningView: some View {
    if showTranslation {
      TappableTranslation(
        card: card,
        text: meaning,
        font: Typography.metadata,
        sample: "meaning",
        alignment: .leading
      )
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  /// The captured lyric line as ruby (saved word tinted) with a leading play button
  /// aligned to the surface line, the line's translation (when shown), and the song
  /// attribution beneath (when the citation is shown).
  private func citation(_ line: String) -> some View {
    PlayableSourceLine(
      card: card,
      tokens: SourceLineCodec.decode(line),
      highlightWord: card.surface,
      buttonSize: 22,
      spacing: Spacing.s,
      surfaceFont: Typography.metadata
    ) {
      if showTranslation { lineTranslationView }
      if showCitation, let citation = card.sourceCitation {
        Text(citation)
          .font(Typography.furigana)
          .foregroundStyle(.tertiary)
      }
    }
    .padding(.top, Spacing.xs)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// The lyric line's translation when shown: the gloss if present, a redacted
  /// placeholder while a fetch is in flight, or the shared tap-to-translate
  /// affordance when neither — the same explicit-tap-only fetch as the word's
  /// meaning above (and a tap on either fills both).
  private var lineTranslationView: some View {
    TappableTranslation(
      card: card,
      text: lineTranslation,
      font: Typography.furigana,
      sample: "translating this line",
      alignment: .leading
    )
  }
}
