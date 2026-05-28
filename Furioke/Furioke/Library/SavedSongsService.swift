import Foundation
import Supabase

/// Reads and writes the user's `songs` table directly through the Supabase client
/// (Supabase is the cross-device source of truth; SwiftData is a local
/// read-through mirror). RLS scopes every row to `auth.uid()`, and the insert
/// policy requires a permanent (non-anonymous) account — iOS sign-in is Google
/// OAuth, so that always holds. The `(user_id, provider, provider_track_id)`
/// unique constraint makes the save an idempotent upsert.
struct SavedSongsService {
  private let auth: AuthService

  init(auth: AuthService) {
    self.auth = auth
  }

  /// Every saved song for the signed-in user (RLS filters to them). Ordering is
  /// applied locally by `savedAt`, so no `order` clause is needed here.
  func fetchAll() async throws -> [SavedSong] {
    let rows: [SongRow] = try await auth.client
      .from("songs")
      .select("provider,provider_track_id,title,artist,album,artwork_url,duration_ms,created_at")
      .execute()
      .value
    return rows.map(\.asSavedSong)
  }

  /// Insert (or no-op update) a saved song. `user_id` must be sent explicitly —
  /// the column has no default — and is taken from the current session.
  func upsert(_ song: SavedSong) async throws {
    let userID = try await auth.client.auth.session.user.id
    let row = SongInsert(
      userID: userID.uuidString.lowercased(),
      provider: song.provider,
      providerTrackID: song.providerTrackID,
      title: song.title,
      artist: song.artist,
      album: song.album,
      durationMs: song.durationMs,
      artworkURL: song.artworkURL
    )
    try await auth.client
      .from("songs")
      .upsert(row, onConflict: "user_id,provider,provider_track_id")
      .execute()
  }

  /// Remove a saved song. RLS scopes the delete to the signed-in user, so matching
  /// on the `(provider, provider_track_id)` unique key is enough; deleting a row
  /// that isn't there is a no-op.
  func delete(provider: String, providerTrackID: String) async throws {
    try await auth.client
      .from("songs")
      .delete()
      .eq("provider", value: provider)
      .eq("provider_track_id", value: providerTrackID)
      .execute()
  }
}

/// The subset of `songs` columns the cache mirror needs. `created_at` decodes via
/// the Supabase client's timestamptz-aware decoder.
private struct SongRow: Decodable {
  let provider: String
  let providerTrackID: String
  let title: String
  let artist: String?
  let album: String?
  let artworkURL: String?
  let durationMs: Int?
  let createdAt: Date

  enum CodingKeys: String, CodingKey {
    case provider, title, artist, album
    case providerTrackID = "provider_track_id"
    case artworkURL = "artwork_url"
    case durationMs = "duration_ms"
    case createdAt = "created_at"
  }

  var asSavedSong: SavedSong {
    SavedSong(
      provider: provider,
      providerTrackID: providerTrackID,
      title: title,
      artist: artist,
      album: album,
      durationMs: durationMs,
      artworkURL: artworkURL,
      savedAt: createdAt
    )
  }
}

private struct SongInsert: Encodable {
  let userID: String
  let provider: String
  let providerTrackID: String
  let title: String
  let artist: String?
  let album: String?
  let durationMs: Int?
  let artworkURL: String?

  enum CodingKeys: String, CodingKey {
    case userID = "user_id"
    case provider, title, artist, album
    case providerTrackID = "provider_track_id"
    case durationMs = "duration_ms"
    case artworkURL = "artwork_url"
  }
}
