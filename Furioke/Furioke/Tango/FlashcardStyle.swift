import SwiftUI

/// Shared text styling for a saved word and its captured line, so the study card
/// (`FlashcardView`) and the browse row (`TangoRow`) render the word at the same
/// weight and design — rounded **semibold** kanji over rounded furigana — and only
/// vary the point size by context. Centralizing the "thickness" here keeps the two
/// surfaces from drifting apart: the strokes read identically whether the word is on
/// a 44-pt prompt face or a list row.
enum FlashcardStyle {
  /// The saved word's kanji run at an explicit point size — used by the fixed-size
  /// study faces, which size themselves from the deck's frame rather than Dynamic
  /// Type so every card is identical.
  static func word(size: CGFloat) -> Font {
    .system(size: size, weight: .semibold, design: .rounded)
  }

  /// The furigana stacked above `word(size:)`, at an explicit point size.
  static func furigana(size: CGFloat) -> Font {
    .system(size: size, weight: .regular, design: .rounded)
  }

  /// The saved word on the browse row: the same rounded semibold weight as the
  /// study faces, but a Dynamic-Type-relative size so list rows scale with the
  /// system text size.
  static let rowWord: Font = .system(.title3, design: .rounded, weight: .semibold)

  /// The furigana above `rowWord`, matching the row's relative scaling.
  static let rowFurigana: Font = Typography.furigana
}
