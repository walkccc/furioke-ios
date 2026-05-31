import Foundation

/// A saved word in the learner's deck, mirroring one row of the Supabase
/// `flashcards` table and `../furioke/lib/flashcards/types.ts`. `surface` is the
/// dedupe + toggle key — the whole word (e.g. 続く or 二人), not a single
/// character. `level`/`dueAt` carry the Leitner spaced-repetition schedule (see
/// `FlashcardSchedule`). `meaning` and `sourceLineTranslation` are per-language
/// gloss maps keyed by translation target (`en` / `ja` / `zh-tw`; Traditional
/// Chinese is `zh-tw`, never `zhHant`), each filled lazily for the active
/// language from `/api/translate` — the deck shows the gloss for whatever
/// language is selected, or fetches just that one on demand. `sourceLine`
/// retains the captured line's furigana annotations in pipe notation
/// (`｜base｜reading｜`) so the card can render it as ruby (`SourceLineCodec`).
/// Timestamps are `Date` — the Supabase client decodes the row's timestamptz
/// columns into them — with `updatedAt` the reconcile tiebreaker, the same
/// last-writer-wins contract `RemoteReadingOverride` uses.
nonisolated struct Flashcard: Equatable, Identifiable {
  let surface: String
  var reading: String
  var meaning: [String: String]
  var sourceTitle: String?
  var sourceArtist: String?
  var sourceLine: String?
  var sourceLineTranslation: [String: String]
  var level: Int
  var dueAt: Date
  var createdAt: Date
  var updatedAt: Date

  var id: String {
    surface
  }

  /// The reading worth showing, or nil when it would only repeat the surface. A
  /// pure-kana saved word (わかる) carries no separate reading; a kanji word
  /// (続く / つづく) does. Callers drop the furigana row and the reveal's reading
  /// line when this is nil so the same kana never prints twice over itself.
  var displayReading: String? {
    reading == surface ? nil : reading
  }

  /// The meaning gloss for `target` (a translation-target code), or `nil` when
  /// that language has not been fetched yet. Empty strings count as absent.
  func meaning(for target: String) -> String? {
    meaning[target].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .flatMap { $0.isEmpty ? nil : $0 }
  }

  /// The captured line's translation for `target`, or `nil` when unfetched.
  func sourceLineTranslation(for target: String) -> String? {
    sourceLineTranslation[target]
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .flatMap { $0.isEmpty ? nil : $0 }
  }
}

/// What capture from the lyric surface provides: the word plus the song context
/// it came from. The schedule fields (`level`/`dueAt`) and timestamps are seeded
/// by `FlashcardsState`, not the caller.
nonisolated struct SaveFlashcardInput: Equatable {
  let surface: String
  let reading: String
  var sourceTitle: String?
  var sourceArtist: String?
  var sourceLine: String?
}

nonisolated enum FlashcardGrade: Equatable {
  case again
  case gotIt
}
