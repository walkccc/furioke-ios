import Foundation

/// A gloss stored per language: a sparse map keyed by translation-target code
/// (`en` / `ja` / `zh-tw`), mirroring the web's `GlossMap`. Only the languages
/// actually fetched are present; the rest fill in lazily on demand. The shared
/// Supabase `meaning` / `source_line_translation` columns are `jsonb` of exactly
/// this shape, so both clients encode/decode it identically.
typealias GlossMap = [String: String]

/// The gloss for one language, trimmed, or nil when it hasn't been fetched yet.
/// Mirrors the web's `glossFor`.
nonisolated func glossFor(_ map: GlossMap?, _ target: String) -> String? {
  let value = map?[target]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  return value.isEmpty ? nil : value
}

/// Serialize a gloss map to the `{"en":"…"}` JSON the `FlashcardEntity` stores;
/// an empty map is `{}`.
nonisolated func encodeGlossMap(_ map: GlossMap) -> String {
  guard !map.isEmpty,
        let data = try? JSONEncoder().encode(map),
        let json = String(data: data, encoding: .utf8)
  else { return "{}" }
  return json
}

/// Decode a stored gloss-map JSON string back into a `GlossMap`; malformed or
/// empty JSON decodes to an empty map.
nonisolated func decodeGlossMap(_ json: String) -> GlossMap {
  guard let data = json.data(using: .utf8),
        let map = try? JSONDecoder().decode(GlossMap.self, from: data)
  else { return [:] }
  return map
}

/// How the learner graded a card: forgot it (re-queue) or remembered it (advance).
/// Maps to the web's `FlashcardGrade` (`again` / `got-it`) and the swipe gestures
/// (left = `.again`, right = `.gotIt`).
nonisolated enum FlashcardGrade {
  case again
  case gotIt
}

/// A saved word in the learner's deck, mirroring one `flashcards` row and the
/// web's `Flashcard` shape. `surface` is the dedupe key — the whole word, e.g.
/// 続く or 二人, never a single character. `meaning` / `sourceLineTranslation` are
/// per-language gloss maps filled on demand; `sourceLine` retains the captured
/// line's furigana in pipe notation (｜base｜reading｜) so the card renders it as
/// ruby (see `SourceLineCodec`). `isPendingSync` drives the deck row's sync badge
/// for a `.local` row awaiting upload.
nonisolated struct Flashcard: Identifiable, Equatable {
  let surface: String
  let reading: String
  var meaning: GlossMap
  let sourceTitle: String?
  let sourceArtist: String?
  let sourceLine: String?
  var sourceLineTranslation: GlossMap
  /// Start time (ms) of the captured source line in its song, for study's
  /// "play the line"; nil when the song had no synced lyrics, or the card was
  /// saved before this was captured. Mirrors the web's `sourceLineStartMs`.
  let sourceLineStartMs: Int?
  /// End time (ms) of the captured source line — the next timed line's start —
  /// so study can play *just* the line and pause there, without needing the
  /// song's lyrics loaded. Nil for the last line, an unsynced song, or an older
  /// card. Mirrors the web's `sourceLineEndMs`.
  let sourceLineEndMs: Int?
  /// The source song's provider + provider track id, captured from the playing
  /// track at save time, so study can start that song (connecting if needed) the
  /// way Library does — not just seek it when it's already loaded. Both nil for a
  /// card saved with nothing playing, or saved before this was captured.
  let sourceProvider: String?
  let sourceTrackID: String?
  var level: Int
  var dueAt: Date
  let createdAt: Date
  var updatedAt: Date
  /// A `.local` row written on-device but not yet uploaded. Display-only; never
  /// persisted to the server.
  var isPendingSync: Bool

  init(
    surface: String,
    reading: String,
    meaning: GlossMap = [:],
    sourceTitle: String? = nil,
    sourceArtist: String? = nil,
    sourceLine: String? = nil,
    sourceLineTranslation: GlossMap = [:],
    sourceLineStartMs: Int? = nil,
    sourceLineEndMs: Int? = nil,
    sourceProvider: String? = nil,
    sourceTrackID: String? = nil,
    level: Int = 0,
    dueAt: Date = .now,
    createdAt: Date = .now,
    updatedAt: Date = .now,
    isPendingSync: Bool = false
  ) {
    self.surface = surface
    self.reading = reading
    self.meaning = meaning
    self.sourceTitle = sourceTitle
    self.sourceArtist = sourceArtist
    self.sourceLine = sourceLine
    self.sourceLineTranslation = sourceLineTranslation
    self.sourceLineStartMs = sourceLineStartMs
    self.sourceLineEndMs = sourceLineEndMs
    self.sourceProvider = sourceProvider
    self.sourceTrackID = sourceTrackID
    self.level = level
    self.dueAt = dueAt
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.isPendingSync = isPendingSync
  }

  var id: String {
    surface
  }

  /// A copy of the card with its reading replaced — used to fold the learner's
  /// per-word furigana override (keyed by `surface`) over the reading captured at
  /// save time, so the deck renders the corrected reading without re-uploading.
  func withReading(_ newReading: String) -> Flashcard {
    Flashcard(
      surface: surface,
      reading: newReading,
      meaning: meaning,
      sourceTitle: sourceTitle,
      sourceArtist: sourceArtist,
      sourceLine: sourceLine,
      sourceLineTranslation: sourceLineTranslation,
      sourceLineStartMs: sourceLineStartMs,
      sourceLineEndMs: sourceLineEndMs,
      sourceProvider: sourceProvider,
      sourceTrackID: sourceTrackID,
      level: level,
      dueAt: dueAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
      isPendingSync: isPendingSync
    )
  }

  /// True when the card is due at or before `now` — mirrors the web's `isDue`.
  func isDue(now: Date = .now) -> Bool {
    dueAt <= now
  }

  /// The song the word was captured from, as `Title · Artist`, for the deck row
  /// citation; nil when neither is known.
  var sourceCitation: String? {
    let parts = [sourceTitle, sourceArtist].compactMap { value -> String? in
      let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
      return (trimmed?.isEmpty ?? true) ? nil : trimmed
    }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }
}

/// What capture from the lyric surface provides: the word plus the song context
/// it came from. The schedule fields (`level` / `dueAt`) are seeded by the store,
/// not the caller. Mirrors the web's `SaveFlashcardInput`.
nonisolated struct SaveFlashcardInput: Equatable {
  let surface: String
  let reading: String
  var sourceTitle: String?
  var sourceArtist: String?
  var sourceLine: String?
  /// Start/end times (ms) of the captured source line, resolved from the song's
  /// synced lyrics at save time; nil when the song has no synced lyrics. `end` is
  /// the next line's start (nil for the last line) so study can play just the line.
  var sourceLineStartMs: Int?
  var sourceLineEndMs: Int?
  /// The playing track's provider + provider track id at save time, so study can
  /// start that song later; nil when nothing is playing.
  var sourceProvider: String?
  var sourceTrackID: String?
}
