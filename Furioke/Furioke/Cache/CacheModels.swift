import Foundation
import SwiftData

/// The four SwiftData entities that back offline reading. They are a *local
/// read-through cache*, not a sync source of truth — cross-device data still
/// flows through Supabase, and there is no CloudKit. The annotated form of the
/// lyrics (kuromoji output + correction map) is deliberately **not** persisted:
/// it is recomputed on every render from `LyricBodyEntity.bodyText` plus the
/// current `OverrideEntity` rows, which is cheaper than maintaining a parallel
/// cache.

/// A saved song mirroring one row of the user's Supabase `songs` table. `id`
/// encodes `provider:providerTrackID`, so a unique constraint on `id` is also the
/// `(provider, providerTrackID)` reconciliation key used by Library sync.
@Model
final class SongEntity {
  #Unique<SongEntity>([\.id])

  var id: String
  var provider: String
  var providerTrackID: String
  var title: String
  var artist: String
  var album: String?
  var artworkURL: String?
  var durationMs: Int
  var savedAt: Date

  init(
    id: String,
    provider: String,
    providerTrackID: String,
    title: String,
    artist: String,
    album: String?,
    artworkURL: String?,
    durationMs: Int,
    savedAt: Date
  ) {
    self.id = id
    self.provider = provider
    self.providerTrackID = providerTrackID
    self.title = title
    self.artist = artist
    self.album = album
    self.artworkURL = artworkURL
    self.durationMs = durationMs
    self.savedAt = savedAt
  }
}

/// The raw LRC (or plain) lyric body exactly as `/api/lyrics` returned it, keyed
/// by track `id` (`provider:providerTrackID`). Modeled by id rather than a hard
/// relationship to `SongEntity` because lyrics are cached for *any* played track,
/// including tracks the user never saved — a relationship would force a song row
/// to exist first, which contradicts "`SongEntity` mirrors the saved songs".
@Model
final class LyricBodyEntity {
  #Unique<LyricBodyEntity>([\.songID])
  #Index<LyricBodyEntity>([\.songID])

  var songID: String
  var lrclibID: String?
  var bodyText: String
  var fetchedAt: Date

  init(songID: String, lrclibID: String?, bodyText: String, fetchedAt: Date) {
    self.songID = songID
    self.lrclibID = lrclibID
    self.bodyText = bodyText
    self.fetchedAt = fetchedAt
  }
}

/// A per-user reading override mirroring one row of `reading_overrides`.
/// `source` distinguishes a local optimistic edit not yet uploaded from one the
/// server has acknowledged. `updatedAt` mirrors the row's `updated_at` and is the
/// tiebreaker when a server pull meets an unsynced local edit (last-writer-wins).
@Model
final class OverrideEntity {
  #Unique<OverrideEntity>([\.userID, \.surface])
  #Index<OverrideEntity>([\.userID, \.surface])

  var userID: String
  var surface: String
  var reading: String
  var source: String
  /// When this reading was last written, in the same clock as the server's
  /// `updated_at`. Defaulted (so existing stores migrate without a schema step) to
  /// `.distantPast`, which makes any server row win the first reconcile — correct
  /// for rows that predate this field, since they were already server-synced.
  var updatedAt: Date = Date.distantPast

  init(userID: String, surface: String, reading: String, source: Source, updatedAt: Date) {
    self.userID = userID
    self.surface = surface
    self.reading = reading
    self.source = source.rawValue
    self.updatedAt = updatedAt
  }

  enum Source: String {
    /// Recorded on-device, not yet persisted server-side.
    case local
    /// Acknowledged by the server (synced down, or a local edit confirmed).
    case synced
    /// Deleted by the user but the server `DELETE` has not landed yet (offline or
    /// failed). Kept as a tombstone — never shown, never annotated — so a `.synced`
    /// row isn't dropped locally only to resurrect on a future server pull. The
    /// reconnect flush drains these, then removes the row. New `.rawValue` only, so
    /// existing stores read back unchanged (no SwiftData migration needed).
    case pendingDelete
  }
}

/// A plain value type for one of the user's overrides crossing the cache ⇄ UI
/// boundary, so the management screen never touches a live `@Model`. `isPendingSync`
/// drives the row's sync badge (a `.local` row awaiting upload); `.pendingDelete`
/// rows are excluded upstream and never become a `ReadingOverride`.
nonisolated struct ReadingOverride: Identifiable, Equatable {
  let surface: String
  let reading: String
  let isPendingSync: Bool

  var id: String {
    surface
  }
}

/// A neutral value type for a saved song crossing the Supabase ⇄ cache boundary,
/// so neither the cache nor the sync service depends on the other's types.
/// `id` is the track identity (`provider:providerTrackID`); `artworkURL` is
/// persisted into `SongEntity` so the Library list can show thumbnails offline.
nonisolated struct SavedSong: Equatable {
  let provider: String
  let providerTrackID: String
  let title: String
  let artist: String?
  let album: String?
  let durationMs: Int?
  let artworkURL: String?
  let savedAt: Date

  var id: String {
    "\(provider):\(providerTrackID)"
  }

  var asEntity: SongEntity {
    SongEntity(
      id: id,
      provider: provider,
      providerTrackID: providerTrackID,
      title: title,
      artist: artist ?? "",
      album: album,
      artworkURL: artworkURL,
      durationMs: durationMs ?? 0,
      savedAt: savedAt
    )
  }
}

/// A saved flashcard mirroring one row of the shared `flashcards` table, keyed
/// per user by `(userID, surface)`. Mirrors `OverrideEntity`'s offline discipline:
/// `source` distinguishes a local optimistic write not yet uploaded from a
/// server-acknowledged one, and `updatedAt` is the last-writer-wins tiebreaker on
/// a server pull. The two gloss maps (`meaning`, `sourceLineTranslation`) and the
/// pipe-annotated `sourceLine` are stored as JSON / text exactly as the web shape,
/// so the same row round-trips through both clients.
@Model
final class FlashcardEntity {
  #Unique<FlashcardEntity>([\.userID, \.surface])
  #Index<FlashcardEntity>([\.userID, \.surface], [\.userID, \.dueAt])

  var userID: String
  var surface: String
  var reading: String
  /// `GlossMap` JSON (`{"en":"…"}`); `{}` when no gloss has been fetched.
  var meaningJson: String
  var sourceTitle: String?
  var sourceArtist: String?
  var sourceLine: String?
  var sourceLineTranslationJson: String
  /// Start/end times (ms) of the captured source line; nil when the song had no
  /// synced lyrics or the row predates these fields. Optional so existing stored
  /// rows migrate to nil automatically.
  var sourceLineStartMs: Int?
  var sourceLineEndMs: Int?
  /// The source song's provider + provider track id, so study can start the song;
  /// optional so existing stored rows migrate to nil automatically.
  var sourceProvider: String?
  var sourceTrackID: String?
  var level: Int
  var dueAt: Date
  var source: String
  var updatedAt: Date
  var createdAt: Date

  init(
    userID: String,
    surface: String,
    reading: String,
    meaningJson: String,
    sourceTitle: String?,
    sourceArtist: String?,
    sourceLine: String?,
    sourceLineTranslationJson: String,
    sourceLineStartMs: Int?,
    sourceLineEndMs: Int?,
    sourceProvider: String?,
    sourceTrackID: String?,
    level: Int,
    dueAt: Date,
    source: Source,
    updatedAt: Date,
    createdAt: Date
  ) {
    self.userID = userID
    self.surface = surface
    self.reading = reading
    self.meaningJson = meaningJson
    self.sourceTitle = sourceTitle
    self.sourceArtist = sourceArtist
    self.sourceLine = sourceLine
    self.sourceLineTranslationJson = sourceLineTranslationJson
    self.sourceLineStartMs = sourceLineStartMs
    self.sourceLineEndMs = sourceLineEndMs
    self.sourceProvider = sourceProvider
    self.sourceTrackID = sourceTrackID
    self.level = level
    self.dueAt = dueAt
    self.source = source.rawValue
    self.updatedAt = updatedAt
    self.createdAt = createdAt
  }

  /// Same three-state sync model as `OverrideEntity.Source`: `local` (written
  /// on-device, not yet uploaded), `synced` (server-acknowledged), `pendingDelete`
  /// (deleted locally, server `DELETE` still owed — kept as a tombstone so a
  /// server pull can't resurrect it).
  enum Source: String {
    case local
    case synced
    case pendingDelete
  }

  /// A plain `Flashcard` value extracted for the UI / sync boundary, so a live
  /// `@Model` never leaves the cache actor. `isPendingSync` reflects a `.local` row.
  var asFlashcard: Flashcard {
    Flashcard(
      surface: surface,
      reading: reading,
      meaning: decodeGlossMap(meaningJson),
      sourceTitle: sourceTitle,
      sourceArtist: sourceArtist,
      sourceLine: sourceLine,
      sourceLineTranslation: decodeGlossMap(sourceLineTranslationJson),
      sourceLineStartMs: sourceLineStartMs,
      sourceLineEndMs: sourceLineEndMs,
      sourceProvider: sourceProvider,
      sourceTrackID: sourceTrackID,
      level: level,
      dueAt: dueAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
      isPendingSync: source == Source.local.rawValue
    )
  }
}

/// A cached whole-body translation for a song in a target language, keyed by
/// `(songID, language)`. `bodyJson` is the raw server payload; the NowPlaying
/// translation toggle decodes and renders it.
@Model
final class TranslationEntity {
  #Unique<TranslationEntity>([\.songID, \.language])
  #Index<TranslationEntity>([\.songID], [\.songID, \.language])

  var songID: String
  var language: String
  var bodyJson: String
  var modelVersion: String
  var generatedAt: Date

  init(songID: String, language: String, bodyJson: String, modelVersion: String,
       generatedAt: Date)
  {
    self.songID = songID
    self.language = language
    self.bodyJson = bodyJson
    self.modelVersion = modelVersion
    self.generatedAt = generatedAt
  }
}
