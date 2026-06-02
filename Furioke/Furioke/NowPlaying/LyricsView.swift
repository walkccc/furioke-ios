import SwiftUI

/// The lyric body rendered inside the NowPlayingSheet: loading / not-found /
/// failed states, plus the annotated lines with furigana above each kanji run.
///
/// When the lyrics are synced (LRC timestamps → `AnnotatedLine.timeMs`), the
/// line whose timing window contains the live `MusicState.positionMs` is
/// highlighted — brighter and larger, with the rest dimmed — and the column
/// auto-scrolls to keep it centered. Tapping a synced line seeks the active
/// provider to that line's
/// start. Plain (un-timed) lyrics render at rest with no highlight or seek.
struct LyricsView: View {
  @Environment(NowPlayingState.self) private var nowPlaying
  @Environment(MusicState.self) private var music

  var body: some View {
    switch nowPlaying.status {
    case .idle:
      Color.clear.frame(height: 0)
    case .loading:
      VStack(spacing: Spacing.s) {
        ProgressView()
        Text("Loading lyrics…")
          .font(Typography.metadata)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    case .notFound:
      message("No lyrics found for this track.")
    case .unavailableOffline:
      message("Lyrics aren't available offline.")
    case .failed:
      message("Couldn't load lyrics. Try again.")
    case .loaded:
      loadedLyrics
    }
  }

  private var loadedLyrics: some View {
    let lines = nowPlaying.lines
    // `synced` reflects whether the body carries timestamps — i.e. is
    // sync-capable — not whether a line is *currently* active. That way the
    // unplayed-line dimming is in place from the moment timed lyrics load,
    // before playback reaches the first line. Plain (un-timed) lyrics stay
    // `synced == false` and render at rest with no dimming.
    let synced = lines.contains(where: { $0.timeMs != nil })
    let active = activeIndex(in: lines)
    let showFurigana = nowPlaying.showFurigana
    let showRomaji = nowPlaying.showRomaji
    let translations = nowPlaying.showTranslation ? nowPlaying.translatedLines : []

    return ScrollViewReader { proxy in
      ScrollView {
        // Lazy so opening the sheet only builds the rows in view — each row is a
        // custom `RubyFlowLayout` that sizes every token, so eagerly laying out a
        // full song's worth up front stalls the zoom transition. Offscreen rows
        // build as they scroll in.
        LazyVStack(alignment: .leading, spacing: Spacing.m) {
          ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
            row(
              line,
              index: index,
              isActive: index == active,
              synced: synced,
              showFurigana: showFurigana,
              showRomaji: showRomaji,
              translation: index < translations.count ? translations[index] : nil
            )
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.xl)
        // Pin the column to the scroll viewport's width so `RubyFlowLayout`
        // always receives a finite width proposal and wraps. Without this the
        // width is inherited through a chain of `maxWidth: .infinity` frames; a
        // greedy sibling (the artwork backdrop) can perturb that chain into an
        // unbounded proposal, at which point the layout lays each line on one
        // row, overflows the screen, and the centered sheet ZStack clips the
        // leading edge of every line.
        .containerRelativeFrame(.horizontal)
      }
      .onChange(of: active) { _, newValue in
        guard let newValue else { return }
        withAnimation(Motion.ease) {
          proxy.scrollTo(newValue, anchor: .center)
        }
      }
      // Reopening the sheet rebuilds this column with the ScrollView reset to
      // the top, and `onChange(of: active)` only fires when the active line
      // *changes* — so without this the already-highlighted line stays off
      // screen until the next line boundary is crossed. Jump (no animation,
      // it's the initial placement) straight to the live active line so it's
      // centered the moment the sheet appears. Deferred to the next runloop so
      // the ScrollView has measured its content before we scroll.
      .onAppear {
        guard let active else { return }
        Task { @MainActor in proxy.scrollTo(active, anchor: .center) }
      }
    }
    // Long-pressing a kanji opens the reading editor as a focus overlay: the
    // column dims and blurs behind it, taps are disabled so a dimmed line can't
    // seek, and a light haptic fires as the editor opens.
    // The dim/blur stays on the column; the floating editor card itself is hosted
    // at the surface level (`AppShell`) so it can ride just above the keyboard
    // instead of being boxed into the lyric column's frame.
    .blur(radius: isEditing ? 6 : 0)
    .disabled(isEditing)
    .animation(Motion.ease, value: isEditing)
    .sensoryFeedback(trigger: isEditing) { _, editing in
      editing ? .impact(weight: .light) : nil
    }
  }

  private var isEditing: Bool {
    nowPlaying.editingReading != nil
  }

  @ViewBuilder
  private func row(
    _ line: AnnotatedLine,
    index: Int,
    isActive: Bool,
    synced: Bool,
    showFurigana: Bool,
    showRomaji: Bool,
    translation: String?
  ) -> some View {
    if line.tokens.isEmpty {
      Color.clear.frame(height: Spacing.s).id(index)
    } else {
      // The highlight is opacity-only: font size, weight, and line metrics stay
      // identical between active and resting lines, so a line lighting up never
      // reflows the column or nudges its neighbours. The expanding frame hands
      // the wrapping layout the full content width so long lines wrap instead of
      // running off the edge.
      RubyLine(
        line: line,
        showFurigana: showFurigana,
        showRomaji: showRomaji,
        translation: translation
      )
      .frame(maxWidth: .infinity, alignment: .leading)
      .opacity(synced && !isActive ? 0.4 : 1)
      .animation(Motion.ease, value: isActive)
      .contentShape(Rectangle())
      .onTapGesture { seek(to: line) }
      .id(index)
    }
  }

  /// The last synced line whose start time has been reached. `nil` when the
  /// body carries no timestamps — which also disables highlight and seek.
  private func activeIndex(in lines: [AnnotatedLine]) -> Int? {
    guard lines.contains(where: { $0.timeMs != nil }) else { return nil }
    let position = music.positionMs
    var result: Int?
    for (index, line) in lines.enumerated() {
      guard let timeMs = line.timeMs else { continue }
      if timeMs <= position { result = index } else { break }
    }
    return result
  }

  private func seek(to line: AnnotatedLine) {
    guard let timeMs = line.timeMs else { return }
    Task { _ = await music.control(.seek(positionMs: timeMs)) }
  }

  private func message(_ text: LocalizedStringKey) -> some View {
    Text(text)
      .font(Typography.body)
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

/// One annotated lyric line as a wrapping flow of ruby cells, with an optional
/// rōmaji row tucked beneath when the reader has it on.
private struct RubyLine: View {
  let line: AnnotatedLine
  let showFurigana: Bool
  let showRomaji: Bool
  let translation: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      // Cells are grouped into words before layout: a saveable content word's
      // cells (変 + わって) become one flow item so the whole word is a single
      // press target and scales together, while every other token stays its own
      // item and wraps independently. See `RubyWord.group`.
      RubyFlowLayout(horizontalSpacing: 0, verticalSpacing: 2) {
        ForEach(Array(RubyWord.group(line.tokens).enumerated()), id: \.offset) { _, word in
          RubyWordView(cells: word, line: line, showFurigana: showFurigana)
        }
      }
      if showRomaji, !line.romaji.isEmpty {
        Text(line.romaji)
          .font(Typography.furigana)
          .foregroundStyle(.secondary)
      }
      if let translation, !translation.isEmpty {
        Text(translation)
          .font(Typography.metadata)
          .foregroundStyle(.secondary)
      }
    }
  }
}

/// Groups a line's flat `RubyToken` stream into the words the interaction layer
/// treats as a unit. A saveable content word is emitted as several cells that
/// share one `wordSurface` (変 + わって, or 置 + き + 忘 + れ); this collapses those
/// consecutive cells into one run so the whole word becomes a single press
/// target. Every other token — particles, punctuation, the non-saveable kana of
/// a plain run — stays a one-cell run so it wraps and behaves independently.
private enum RubyWord {
  static func group(_ tokens: [RubyToken]) -> [[RubyToken]] {
    var runs: [[RubyToken]] = []
    for token in tokens {
      // Extend the current run only when this cell is a saveable continuation of
      // the same word — matched on `wordSurface`, shared across a word's okurigana
      // cells. Non-saveable tokens never merge, so they can't swallow a neighbour.
      if token.saveable,
         let last = runs.last?.last,
         last.saveable,
         last.wordSurface == token.wordSurface
      {
        runs[runs.count - 1].append(token)
      } else {
        runs.append([token])
      }
    }
    return runs
  }
}

/// One word on the lyric surface: the shared read-only `RubyCell` visuals for
/// each of its cells, with the surface's interactive behavior layered on the
/// *whole word*. A saveable content word that contains kanji (see
/// `RubyToken.saveable`) is interactive — a press-down response while held and the
/// reading editor on long-press — and all of its cells (変 + わって) respond
/// together because they form a single gesture target. A non-saveable run (one
/// cell: a particle, punctuation, plain kana) just renders. A short tap falls
/// through to the line's tap-to-seek.
private struct RubyWordView: View {
  let cells: [RubyToken]
  /// The line this word sits in, threaded through so a flashcard captured from the
  /// long-press editor keeps its source line.
  let line: AnnotatedLine
  let showFurigana: Bool
  @Environment(NowPlayingState.self) private var nowPlaying
  @Environment(FlashcardsState.self) private var flashcards
  @State private var pressing = false

  /// The word these cells belong to — every cell of a saveable run shares its
  /// `wordSurface`/`wordReading`/`saveable`, and a non-saveable run is a single
  /// cell, so the first cell stands for the whole word.
  private var word: RubyToken {
    cells[0]
  }

  /// Whether the word can be long-pressed to correct its reading: a saveable
  /// content word that contains kanji. The whole 変わって is pressable; kana-only
  /// words have no reading to correct, and particles / punctuation stay inert.
  private var isInteractive: Bool {
    word.saveable && FuriganaAnnotator.containsKanji(word.wordSurface)
  }

  /// A saved content word carries the deck marker — a thin accent underline,
  /// distinct from the opacity-only active-line emphasis. Empty when signed out
  /// (`savedSurfaces` is empty), so the marker only appears for a signed-in deck.
  private var isSaved: Bool {
    flashcards.isSaved(word.wordSurface)
  }

  var body: some View {
    // The word's cells laid out tight; zero spacing keeps okurigana abutting so
    // a saved word's underline reads as one continuous bar under the whole word.
    let run = HStack(spacing: 0) {
      ForEach(Array(cells.enumerated()), id: \.offset) { _, token in
        RubyCell(token: token, showFurigana: showFurigana)
      }
    }
    // The deck marker lives under the word as a thin accent rule — present
    // whenever the word is in the deck, on any line, never confused with the
    // active-line brightness.
    .overlay(alignment: .bottom) {
      if isSaved {
        Capsule()
          .fill(Color.accentColor.opacity(0.55))
          .frame(height: 2)
          .offset(y: 2)
      }
    }

    if isInteractive {
      run
        // The whole word scales as one — press 変 or わって and the entire
        // 変わって depresses together, because the cells share this one target.
        .scaleEffect(pressing ? 0.9 : 1)
        .animation(Motion.pop, value: pressing)
        .contentShape(Rectangle())
        // Edit the *whole word*: the override is keyed by `wordSurface` so it
        // matches `CorrectionMap` on re-render (see `RubyToken`). The line is
        // passed so a flashcard saved here keeps its captured source line.
        .onLongPressGesture(minimumDuration: 0.4) {
          nowPlaying.beginEditing(surface: word.wordSurface, reading: word.wordReading, line: line)
        } onPressingChanged: { pressing = $0 }
        // The long-press is a touch gesture VoiceOver can't perform, so the same
        // edit is exposed as a named custom action. The word's cells are combined
        // into one element so it is announced once, then the action is offered.
        .accessibilityElement(children: .combine)
        .accessibilityHint("Corrects the reading")
        .accessibilityAction(named: Text("Correct reading")) {
          nowPlaying.beginEditing(surface: word.wordSurface, reading: word.wordReading, line: line)
        }
    } else {
      run
    }
  }
}
