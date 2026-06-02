import SwiftUI

/// The study front-face recognition ladder — each mode strips one reading aid, so
/// the prompt gets harder left to right. The reveal (back face) always completes
/// the full word regardless of mode. The choice persists across sessions via
/// `@AppStorage` and applies to the whole session.
enum StudyMode: String, CaseIterable, Identifiable {
  /// Kanji with per-kanji furigana ruby (the lyric-surface alignment).
  case glance
  /// Kanji with no furigana — recall the reading.
  case read
  /// Hiragana reading only, no kanji. Aimed at native Chinese readers, for whom
  /// the kanji is transparent but the Japanese pronunciation is the real test.
  case hiragana
  /// The captured lyric line with the saved word blanked out — recall the word
  /// in the sentence it was heard sung in. A card with no usable source line
  /// falls back to the Glance prompt.
  case cloze

  var id: String {
    rawValue
  }

  var label: LocalizedStringKey {
    switch self {
    case .glance: "Glance"
    case .read: "Read"
    case .hiragana: "Hiragana"
    case .cloze: "In lyrics"
    }
  }

  /// A short description for the display-mode menu so the ladder reads clearly.
  var detail: LocalizedStringKey {
    switch self {
    case .glance: "Kanji with furigana"
    case .read: "Kanji only"
    case .hiragana: "Reading only"
    case .cloze: "Word blanked in its lyric line"
    }
  }
}
