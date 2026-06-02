import Foundation
import Supabase

/// Reads and writes the user's deck directly through the Supabase client against
/// the shared `flashcards` table (Supabase is the cross-device source of truth;
/// SwiftData is a local read-through mirror), mirroring `SavedSongsService`. RLS
/// scopes every row to `auth.uid()`, the insert/update policies require a
/// permanent (non-anonymous) account — iOS sign-in is Google OAuth, so that always
/// holds — and the `(user_id, surface)` unique constraint makes a save an
/// idempotent upsert.
struct FlashcardsService {
  private let auth: AuthService

  init(auth: AuthService) {
    self.auth = auth
  }

  /// Every card for the signed-in user (RLS filters to them), carrying `updated_at`
  /// so the cache can reconcile last-writer-wins against local edits.
  func fetchAll() async throws -> [Flashcard] {
    let rows: [FlashcardRow] = try await auth.client
      .from("flashcards")
      .select(
        "surface,reading,meaning,source_title,source_artist,source_line,source_line_translation,source_line_start_ms,source_line_end_ms,source_provider,source_track_id,level,due_at,created_at,updated_at"
      )
      .execute()
      .value
    return rows.map(\.asFlashcard)
  }

  /// Insert or update a card. `user_id` must be sent explicitly — the column has no
  /// default — and comes from the session. The whole card is sent so the upsert is
  /// a complete row (a grade or gloss write carries the unchanged fields through).
  func upsert(_ card: Flashcard) async throws {
    let userID = try await auth.client.auth.session.user.id
    let row = FlashcardInsert(
      userID: userID.uuidString.lowercased(),
      surface: card.surface,
      reading: card.reading,
      meaning: card.meaning,
      sourceTitle: card.sourceTitle,
      sourceArtist: card.sourceArtist,
      sourceLine: card.sourceLine,
      sourceLineTranslation: card.sourceLineTranslation,
      sourceLineStartMs: card.sourceLineStartMs,
      sourceLineEndMs: card.sourceLineEndMs,
      sourceProvider: card.sourceProvider,
      sourceTrackID: card.sourceTrackID,
      level: card.level,
      dueAt: Self.iso.string(from: card.dueAt),
      updatedAt: Self.iso.string(from: card.updatedAt)
    )
    try await auth.client
      .from("flashcards")
      .upsert(row, onConflict: "user_id,surface")
      .execute()
  }

  /// Remove a card. RLS scopes the delete to the signed-in user, so matching on
  /// `surface` is enough; deleting a row that isn't there is a no-op.
  func delete(surface: String) async throws {
    let userID = try await auth.client.auth.session.user.id
    try await auth.client
      .from("flashcards")
      .delete()
      .eq("user_id", value: userID.uuidString.lowercased())
      .eq("surface", value: surface)
      .execute()
  }

  /// ISO-8601 with fractional seconds — a `timestamptz`-parseable literal, so the
  /// dates round-trip regardless of the client encoder's default date strategy.
  private static let iso: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()
}

/// The `flashcards` columns the cache mirror needs. `meaning` /
/// `source_line_translation` decode jsonb → `GlossMap`; the timestamps decode via
/// the Supabase client's timestamptz-aware decoder.
private struct FlashcardRow: Decodable {
  let surface: String
  let reading: String
  let meaning: GlossMap
  let sourceTitle: String?
  let sourceArtist: String?
  let sourceLine: String?
  let sourceLineTranslation: GlossMap
  let sourceLineStartMs: Int?
  let sourceLineEndMs: Int?
  let sourceProvider: String?
  let sourceTrackID: String?
  let level: Int
  let dueAt: Date
  let createdAt: Date
  let updatedAt: Date

  enum CodingKeys: String, CodingKey {
    case surface, reading, meaning, level
    case sourceTitle = "source_title"
    case sourceArtist = "source_artist"
    case sourceLine = "source_line"
    case sourceLineTranslation = "source_line_translation"
    case sourceLineStartMs = "source_line_start_ms"
    case sourceLineEndMs = "source_line_end_ms"
    case sourceProvider = "source_provider"
    case sourceTrackID = "source_track_id"
    case dueAt = "due_at"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }

  var asFlashcard: Flashcard {
    Flashcard(
      surface: surface,
      reading: reading,
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
      updatedAt: updatedAt
    )
  }
}

private struct FlashcardInsert: Encodable {
  let userID: String
  let surface: String
  let reading: String
  let meaning: GlossMap
  let sourceTitle: String?
  let sourceArtist: String?
  let sourceLine: String?
  let sourceLineTranslation: GlossMap
  let sourceLineStartMs: Int?
  let sourceLineEndMs: Int?
  let sourceProvider: String?
  let sourceTrackID: String?
  let level: Int
  let dueAt: String
  let updatedAt: String

  enum CodingKeys: String, CodingKey {
    case userID = "user_id"
    case surface, reading, meaning, level
    case sourceTitle = "source_title"
    case sourceArtist = "source_artist"
    case sourceLine = "source_line"
    case sourceLineTranslation = "source_line_translation"
    case sourceLineStartMs = "source_line_start_ms"
    case sourceLineEndMs = "source_line_end_ms"
    case sourceProvider = "source_provider"
    case sourceTrackID = "source_track_id"
    case dueAt = "due_at"
    case updatedAt = "updated_at"
  }
}
