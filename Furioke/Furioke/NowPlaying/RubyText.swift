import SwiftUI

/// A read-only run of ruby cells — kanji with their stored readings stacked
/// above — laid out with `RubyFlowLayout`. Shared by the lyric surface (where
/// `LyricsView` layers long-press editing + saved markers on top of `RubyCell`)
/// and the flashcard deck / study card, which render a captured source line. The
/// reading is supplied in the tokens, so this never tokenizes.
struct RubyText: View {
  let tokens: [RubyToken]
  var showFurigana: Bool = true
  /// When set, every cell belonging to this word (matched on `wordSurface`, so a
  /// kanji run and its okurigana light up together) is tinted with the accent —
  /// used by the flashcard study back-face to point out the saved word inside its
  /// captured lyric line.
  var highlightWord: String? = nil
  /// Wrap cells across rows with `RubyFlowLayout` (the lyric surface, where a long
  /// line must flow). When false the cells stay on a single row in an `HStack` —
  /// the flashcard word faces render one short word and must never break a kanji
  /// run off from its okurigana (届 / かなかった), so they opt out of wrapping.
  var wraps: Bool = true
  /// The kanji-run font. Defaults to the lyric-surface size; the study card's
  /// Glance prompt overrides this so its kanji match the `Read` prompt exactly,
  /// with furigana simply stacked above.
  var surfaceFont: Font = Typography.lyricRest
  /// The reading font, scaled to sit proportionally above `surfaceFont`.
  var furiganaFont: Font = Typography.furigana
  /// The reading colour for non-highlighted cells. Defaults to `.secondary` for
  /// the lyric surface; the flashcard back overrides it with a stronger tone so
  /// small ruby stays legible over the frosted card material.
  var furiganaStyle: AnyShapeStyle = .init(.secondary)

  var body: some View {
    if wraps {
      RubyFlowLayout(horizontalSpacing: 0, verticalSpacing: 2) {
        cells
      }
    } else {
      HStack(alignment: .bottom, spacing: 0) {
        cells
      }
    }
  }

  private var cells: some View {
    ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
      RubyCell(
        token: token,
        showFurigana: showFurigana,
        highlighted: isHighlighted(token),
        surfaceFont: surfaceFont,
        furiganaFont: furiganaFont,
        furiganaStyle: furiganaStyle
      )
    }
  }

  private func isHighlighted(_ token: RubyToken) -> Bool {
    guard let highlightWord, !highlightWord.isEmpty else { return false }
    return token.wordSurface == highlightWord
  }
}

/// One ruby cell: a kanji run with its reading stacked above, or a plain run with
/// the reading slot reserved (blank) so baselines line up across a row. The font
/// is fixed — any active/resting emphasis is applied by callers via opacity,
/// never here — so the cell's height never changes. With furigana off the
/// reading row is dropped entirely, tightening the line to surface-only.
struct RubyCell: View {
  let token: RubyToken
  var showFurigana: Bool = true
  /// Tints this cell with the accent. Off by default so the surface keeps
  /// inheriting its caller's foreground (e.g. the dimmed source line).
  var highlighted: Bool = false
  var surfaceFont: Font = Typography.lyricRest
  var furiganaFont: Font = Typography.furigana
  /// Reading colour for the non-highlighted state; see `RubyText.furiganaStyle`.
  var furiganaStyle: AnyShapeStyle = .init(.secondary)

  var body: some View {
    VStack(spacing: 0) {
      if showFurigana {
        Text(token.reading ?? " ")
          .font(furiganaFont)
          .foregroundStyle(highlighted ? AnyShapeStyle(Color.accentColor) : furiganaStyle)
          .opacity(token.reading == nil ? 0 : 1)
      }
      surface
    }
    .fixedSize()
  }

  @ViewBuilder
  private var surface: some View {
    let text = Text(token.surface).font(surfaceFont)
    if highlighted {
      text.foregroundStyle(Color.accentColor)
    } else {
      text
    }
  }
}
