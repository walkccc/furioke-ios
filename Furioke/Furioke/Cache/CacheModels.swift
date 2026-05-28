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
