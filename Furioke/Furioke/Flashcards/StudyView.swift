import SwiftUI

/// Spaced-repetition study mode: flips through the cards due now (seeded once on
/// entry), grading "Again" (reset + re-queue this session) or "Got it" (advance
/// the schedule). Grades persist through `FlashcardsState`, which works offline.
///
/// The card's *prompt face* is chosen by `StudyMode` — a recognition ladder from
/// kanji-with-furigana (Glance) through kanji-only (Read) to reading-only
/// (Hiragana) — and the reveal completes whatever the prompt withheld (kanji ·
/// reading · meaning · lyric). The captured lyric is always shown on the back with
/// the saved word highlighted. The meaning and the source-line translation are
/// fetched on reveal and may fill in a moment later.
struct StudyView: View {
  @Environment(FlashcardsState.self) private var flashcards
  @Environment(PreferencesState.self) private var preferences

  /// The session queue, seeded from the due cards on entry. "Again" re-queues a
  /// card to the end; "Got it" drops it. Independent of the persisted deck.
  @State private var queue: [Flashcard] = []
  @State private var revealed = false
  @State private var seeded = false

  /// The active language's gloss key; glosses are shown and fetched for this.
  private var target: String { preferences.language.translationTarget }

  /// The recognition ladder, persisted across sessions — the only study setting.
  @AppStorage(FlashcardDisplayDefaults.studyMode) private var studyModeRaw = StudyMode.read.rawValue

  private var mode: StudyMode { StudyMode(rawValue: studyModeRaw) ?? .read }

  var body: some View {
    Group {
      if let card = queue.first {
        cardSurface(for: liveCard(card))
      } else {
        EmptyState(
          systemImage: "checkmark.circle",
          title: "Nothing due",
          message: "You're all caught up. Save more words, or come back when cards are due."
        )
      }
    }
    .navigationTitle("Study")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Picker("Display mode", selection: $studyModeRaw) {
            ForEach(StudyMode.allCases) { mode in
              Text(mode.title).tag(mode.rawValue)
            }
          }
          .pickerStyle(.inline)
        } label: {
          Image(systemName: "textformat")
        }
      }
    }
    .background(ArtworkBackdrop(url: nil))
    .onAppear {
      guard !seeded else { return }
      seeded = true
      queue = flashcards.dueCards()
    }
    // Switching language while a card is revealed fetches the now-active
    // language's gloss if the card lacks it; languages already present are
    // untouched (the fetch is a no-op for them).
    .onChange(of: preferences.language) {
      if revealed, let card = queue.first {
        Task { await flashcards.fetchCardContext(surface: card.surface) }
      }
    }
  }

  /// The latest persisted version of a queued card, so a meaning fetched on
  /// reveal shows up; falls back to the queued snapshot if it was just removed.
  private func liveCard(_ card: Flashcard) -> Flashcard {
    flashcards.cards.first { $0.surface == card.surface } ?? card
  }

  private func cardSurface(for card: Flashcard) -> some View {
    VStack(spacing: Spacing.xl) {
      Spacer(minLength: 0)
      Surface(material: Materials.contentSurface, cornerRadius: Radii.xl) {
        VStack(spacing: Spacing.l) {
          prompt(card)
          if revealed {
            Divider()
            reveal(card)
          }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity)
      }
      Spacer(minLength: 0)
      controls(for: card)
    }
    .padding(Spacing.l)
  }

  // MARK: - Prompt face (mode-driven)

  /// What the learner sees before revealing — the facet the chosen rung tests.
  @ViewBuilder
  private func prompt(_ card: Flashcard) -> some View {
    switch mode {
    case .glance:
      // Identical to the `read` prompt — the kanji at `pageTitle` — but with each
      // kanji run carrying its own reading above it (色褪 with いろあ, not the whole
      // word's kana over the whole word). Toggling Glance ⇄ Read keeps the kanji
      // put; Glance just adds the ruby.
      RubyText(
        tokens: FuriganaAnnotator.align(surface: card.surface, reading: card.reading),
        showFurigana: true,
        surfaceFont: Typography.pageTitle,
        furiganaFont: .system(.callout, design: .rounded)
      )
      // Size to content so the parent VStack centers it, the way the `read`
      // prompt's plain Text is centered (the flow layout itself is leading-aligned).
      .fixedSize(horizontal: true, vertical: false)
    case .read:
      Text(card.surface)
        .font(Typography.pageTitle)
    case .hiragana:
      Text(card.reading)
        .font(Typography.pageTitle)
    }
  }

  // MARK: - Reveal (the complement)

  /// Completes the word: fills in whichever facets the prompt withheld, then the
  /// meaning and the captured source line.
  @ViewBuilder
  private func reveal(_ card: Flashcard) -> some View {
    // The kanji is the answer when the prompt showed only the reading — but a
    // pure-kana word (no distinct reading) is its own surface, so the prompt
    // already showed it; nothing to reveal.
    if mode == .hiragana, card.displayReading != nil {
      Text(card.surface)
        .font(Typography.pageTitle)
    }
    // The reading is the answer when the prompt showed only the kanji; skip it
    // when it would just repeat the surface (a pure-kana word).
    if mode == .read, let reading = card.displayReading {
      Text(reading)
        .font(Typography.lyricActive)
        .foregroundStyle(.secondary)
    }
    if let meaning = card.meaning(for: target) {
      Text(meaning)
        .font(Typography.body)
        .multilineTextAlignment(.center)
    }
    if let line = card.sourceLine, !line.isEmpty {
      sourceBlock(card: card, line: line)
        .padding(.top, Spacing.s)
    }
  }

  /// The captured lyric as a left-aligned quote block: a leading accent rule, the
  /// ruby line with the saved word highlighted, and its translation sharing one
  /// left edge — so the line reads as an intentional source quote, not a stray
  /// left-shoved row in a centered card.
  private func sourceBlock(card: Flashcard, line: String) -> some View {
    HStack(alignment: .top, spacing: Spacing.m) {
      RoundedRectangle(cornerRadius: 1.5, style: .continuous)
        .fill(.secondary.opacity(0.35))
        .frame(width: 3)
      VStack(alignment: .leading, spacing: Spacing.xs) {
        RubyText(
          tokens: SourceLineCodec.parse(line),
          showFurigana: true,
          highlightWord: card.surface
        )
        .foregroundStyle(.secondary)
        if let translation = card.sourceLineTranslation(for: target) {
          Text(translation)
            .font(Typography.metadata)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.leading)
        }
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity)
    .fixedSize(horizontal: false, vertical: true)
  }

  // MARK: - Controls

  @ViewBuilder
  private func controls(for card: Flashcard) -> some View {
    if revealed {
      HStack(spacing: Spacing.m) {
        controlButton("Again") { grade(.again) }
        controlButton("Got it") { grade(.gotIt) }
      }
    } else {
      controlButton("Reveal") {
        withAnimation(Motion.pop) { revealed = true }
        Task { await flashcards.fetchCardContext(surface: card.surface) }
      }
    }
  }

  private func controlButton(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title)
        .font(Typography.sectionTitle)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.m)
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .glassEffect(Materials.controlTier.glass, in: Capsule())
  }

  private func grade(_ grade: FlashcardGrade) {
    guard let card = queue.first else { return }
    flashcards.grade(surface: card.surface, grade)
    var rest = Array(queue.dropFirst())
    // "Again" re-queues the card (reset to due-now) at the end of this session.
    if grade == .again, let requeued = flashcards.cards.first(where: { $0.surface == card.surface }) {
      rest.append(requeued)
    }
    revealed = false
    withAnimation(Motion.pop) { queue = rest }
  }
}
