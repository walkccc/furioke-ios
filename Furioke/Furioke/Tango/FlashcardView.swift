import SwiftUI

/// A single flashcard: the front shows the prompt face for the selected
/// `StudyMode`, the back completes the word as furigana ruby with its translation,
/// the captured lyric line, and that line's translation. The card fills whatever
/// frame the deck gives it (so every card is the same size) and clips its content;
/// `isFlipped` drives a 3D Y-axis flip with the back counter-rotated so it never
/// reads mirrored. Purely presentational — the interactive top card layers
/// tap/swipe on top.
struct FlashcardView: View {
  let card: Flashcard
  let mode: StudyMode
  let isFlipped: Bool

  var body: some View {
    ZStack {
      // Both faces stay mounted (opacity-crossfaded), so the hidden face's inline
      // play button must not intercept taps — only the visible face takes hits.
      FlashcardFront(card: card, mode: mode)
        .opacity(isFlipped ? 0 : 1)
        .allowsHitTesting(!isFlipped)
      FlashcardBack(card: card)
        .opacity(isFlipped ? 1 : 0)
        .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
        .allowsHitTesting(isFlipped)
    }
    .padding(Spacing.xl)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .flashcardSurface()
    .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
  }
}

/// A blank card surface for the cards stacked behind the top one — no content, so
/// the deck reads as depth rather than overlapping words bleeding through.
struct EmptyFlashcardView: View {
  var body: some View {
    Color.clear
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .flashcardSurface()
  }
}

private enum CardShape {
  static let shape = RoundedRectangle(cornerRadius: Radii.xxl, style: .continuous)
}

private extension View {
  /// The shared card surface: a content panel with a soft edge and shadow, legible
  /// over the artwork backdrop *or* a plain background. Softened off the stark pure
  /// white / near-black `systemBackground` toward a calmer surface tone with a faint
  /// translucency, so the card reads gentler against the backdrop. Kept near-opaque
  /// on purpose: a fully translucent material let the next card in the deck bleed
  /// through during the 3D flip, so the fill stays a high-opacity solid. Content is
  /// clipped to the rounded shape so a long back face never spills past the card.
  func flashcardSurface() -> some View {
    modifier(FlashcardSurface())
  }
}

/// Backs `flashcardSurface()` so both the fill and the edge can adapt to the colour
/// scheme: in dark mode the card sits on a softened dark-grey surface, where a
/// 6%-primary hairline vanishes, so the border is brightened to a clearly visible
/// white edge; in light mode it keeps crisp white with a 6%-primary hairline.
private struct FlashcardSurface: ViewModifier {
  @Environment(\.colorScheme) private var colorScheme

  private var borderColor: Color {
    colorScheme == .dark ? Color.white.opacity(0.18) : Color.primary.opacity(0.06)
  }

  /// The card fill, softened only where it helps: dark mode steps off the stark
  /// near-black `systemBackground` to a calmer `secondarySystemBackground` dark-grey;
  /// light mode keeps the crisp pure-white `systemBackground`, which reads cleaner
  /// than a grey there. Both carry a slight transparency so a hint of the backdrop
  /// shows through, without the deck-bleed a full material would cause during the flip.
  private var fillColor: Color {
    let base = colorScheme == .dark ? Color(.secondarySystemBackground) : Color(.systemBackground)
    return base.opacity(0.9)
  }

  func body(content: Content) -> some View {
    content
      .clipShape(CardShape.shape)
      .background(fillColor, in: CardShape.shape)
      .overlay { CardShape.shape.strokeBorder(borderColor) }
      .shadow(color: .black.opacity(0.12), radius: 14, y: 8)
  }
}

/// The prompt face: the word in the selected recognition mode, centered both ways.
private struct FlashcardFront: View {
  let card: Flashcard
  let mode: StudyMode

  private var wordFont: Font {
    FlashcardStyle.word(size: 44)
  }

  var body: some View {
    prompt
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  @ViewBuilder
  private var prompt: some View {
    switch mode {
    case .glance:
      glancePrompt
    case .read:
      // Size to the word's own width, then center it in the card both ways.
      Text(card.surface).font(wordFont).fixedSize(horizontal: true, vertical: false)
    case .hiragana:
      Text(card.reading).font(wordFont).fixedSize(horizontal: true, vertical: false)
    case .cloze:
      clozePrompt
    }
  }

  /// The Glance face — kanji with per-kanji furigana ruby. Also the per-card
  /// fallback for Cloze when a card has no usable source line.
  private var glancePrompt: some View {
    RubyText(
      tokens: FuriganaAnnotator.align(surface: card.surface, reading: card.reading),
      showFurigana: true,
      wraps: false,
      surfaceFont: wordFont,
      furiganaFont: FlashcardStyle.furigana(size: 18),
      furiganaStyle: AnyShapeStyle(.primary.opacity(0.6))
    )
    // Size to the word's own width (the ruby flow layout otherwise fills the
    // card and left-aligns), then center it in the card both ways.
    .fixedSize(horizontal: true, vertical: false)
  }

  /// The Cloze face — the captured lyric line as ruby with the saved word's
  /// cells replaced by a blank, so the learner recalls the word in context. The
  /// line wraps within the card, unlike the single-word faces. Falls back to the
  /// Glance face when the card has no source line, or its surface isn't found in
  /// the line.
  @ViewBuilder
  private var clozePrompt: some View {
    if let tokens = clozeTokens {
      // The play button sits on the line's first surface row; the line wraps within
      // the card.
      PlayableSourceLine(
        card: card,
        tokens: tokens,
        buttonSize: 28,
        surfaceFont: FlashcardStyle.word(size: 26),
        furiganaFont: FlashcardStyle.furigana(size: 13),
        furiganaStyle: AnyShapeStyle(.primary.opacity(0.6))
      ) {
        EmptyView()
      }
    } else {
      glancePrompt
    }
  }

  /// The source-line ruby cells with every run of the saved word collapsed to a
  /// single blank cell, or nil when the card has no source line or its surface
  /// doesn't appear in the line (so the caller falls back to Glance). Matches the
  /// saved word on `wordSurface`, exactly as the back-face highlight does.
  private var clozeTokens: [RubyToken]? {
    guard let line = card.sourceLine else { return nil }
    let decoded = SourceLineCodec.decode(line)
    guard decoded.contains(where: { $0.wordSurface == card.surface }) else { return nil }

    var result: [RubyToken] = []
    var i = decoded.startIndex
    while i < decoded.endIndex {
      guard decoded[i].wordSurface == card.surface else {
        result.append(decoded[i])
        i = decoded.index(after: i)
        continue
      }
      // Collapse the whole run of the saved word into one reading-less blank, so
      // the furigana never gives the answer away.
      var next = decoded.index(after: i)
      while next < decoded.endIndex, decoded[next].wordSurface == card.surface {
        next = decoded.index(after: next)
      }
      let blank = String(repeating: "＿", count: max(2, card.surface.count))
      result.append(RubyToken(
        surface: blank,
        reading: nil,
        wordSurface: card.surface,
        wordReading: card.surface
      ))
      i = next
    }
    return result
  }
}

/// The reveal: the word as furigana ruby, its active-language meaning (the word's
/// translation), and the captured lyric line (with the saved word tinted) plus
/// that line's translation, in a subtle quote panel. Centered as a column so the
/// layout is consistent card to card.
private struct FlashcardBack: View {
  let card: Flashcard
  @Environment(PreferencesState.self) private var preferences

  private var target: String {
    preferences.translationTarget
  }

  private var meaning: String? {
    glossFor(card.meaning, target)
  }

  private var lineTranslation: String? {
    glossFor(card.sourceLineTranslation, target)
  }

  var body: some View {
    VStack(spacing: Spacing.l) {
      VStack(spacing: Spacing.s) {
        RubyText(
          tokens: FuriganaAnnotator.align(surface: card.surface, reading: card.reading),
          showFurigana: true,
          wraps: false,
          surfaceFont: FlashcardStyle.word(size: 32),
          furiganaFont: FlashcardStyle.furigana(size: 15),
          furiganaStyle: AnyShapeStyle(.primary.opacity(0.75))
        )
        .fixedSize(horizontal: true, vertical: false)
        // The word's translation in the active language: the gloss once present, a
        // loading placeholder while the deck's on-flip prefetch is in flight, or a
        // tap-to-translate placeholder when neither — fetching it on demand.
        TappableTranslation(
          card: card,
          text: meaning,
          font: Typography.body,
          sample: "meaning",
          alignment: .center
        )
      }
      if let line = card.sourceLine {
        sourceBlock(line)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  /// The captured lyric line as a soft quote panel — the line as ruby with the
  /// saved word tinted (no leading rule), and the line's translation beneath.
  /// Parsed from the stored pipe annotation, never re-tokenized.
  private func sourceBlock(_ line: String) -> some View {
    // The play button leads the block, centred on the line's first surface row, with
    // the line and its translation stacked to the right.
    PlayableSourceLine(
      card: card,
      tokens: SourceLineCodec.decode(line),
      highlightWord: card.surface
    ) {
      // The lyric line's translation in the active language: the gloss once
      // present, a loading placeholder while a fetch is in flight, or a
      // tap-to-translate placeholder when neither.
      TappableTranslation(
        card: card,
        text: lineTranslation,
        font: Typography.metadata,
        sample: "translating this line",
        alignment: .leading
      )
    }
    .fixedSize(horizontal: false, vertical: true)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(Spacing.m)
    .background(
      Color.primary.opacity(0.04),
      in: RoundedRectangle(cornerRadius: Radii.md, style: .continuous)
    )
  }
}

/// A translation slot — used on the study back face and in the browse deck's rows:
/// the active-language gloss once it's present, a redacted loading placeholder while
/// a fetch is in flight, or — when neither — a tap-to-translate affordance that
/// requests the card's translation on demand. The on-demand fetch
/// (`FlashcardsState.glossed`) routes a spent daily quota through the shared
/// out-of-quota toast, so a tap never fails silently. Crucially the quota notice
/// only ever fires from that explicit tap — nothing here translates on appearance.
/// One tap fetches both the word's meaning and the line's translation, so a tap on
/// either slot also fills the other.
struct TappableTranslation: View {
  let card: Flashcard
  /// The resolved gloss, or nil when it hasn't been fetched yet.
  let text: String?
  let font: Font
  /// Sizes the loading placeholder so the layout holds its place.
  let sample: LocalizedStringKey
  var alignment: TextAlignment = .leading

  @Environment(FlashcardsState.self) private var flashcards

  var body: some View {
    if let text {
      Text(text)
        .font(font)
        // Translations read as a secondary, lighter layer beneath the word itself —
        // one shared treatment for every slot (study back face and browse rows): a
        // regular weight pinned here keeps the boldness uniform no matter which font
        // token (some carry .medium) the slot passes in.
        .fontWeight(.regular)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(alignment)
    } else if flashcards.isGlossing(card.surface) {
      TranslationPlaceholder(font: font, sample: sample, alignment: alignment)
        .foregroundStyle(.secondary)
    } else {
      Button {
        Task { await flashcards.glossed(card) }
      } label: {
        // The affordance keeps the slot's font for size (so Dynamic Type scales it
        // with the surrounding text) but pins a single weight, so the tap-to-translate
        // call-to-action reads at the same boldness in every slot — the browse rows
        // and the study back face alike — regardless of the slot's own font weight.
        Text("Tap to translate")
          .font(font)
          .fontWeight(.semibold)
          .foregroundStyle(Color.accentColor)
          .multilineTextAlignment(alignment)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityHint("Requests this card's translation")
    }
  }
}
