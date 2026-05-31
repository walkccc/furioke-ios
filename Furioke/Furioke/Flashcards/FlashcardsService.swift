import Foundation
import Supabase

/// Reads and writes the user's deck directly through the Supabase client against
/// the `flashcards` table — the same table the web app uses. RLS scopes every
/// row to `auth.uid()` and restricts inserts/updates to permanent accounts; iOS
/// sign-in is Google OAuth, so that always holds. The `(user_id, surface)` unique
/// constraint makes the save an idempotent upsert. This mirrors
/// `SavedSongsService` exactly — flashcards are pure RLS-protected CRUD, so they
/// go direct rather than through a Workers route (a route would only
/// re-implement the ownership scoping RLS already enforces).
struct FlashcardsService {
  private let auth: AuthService

  init(auth: AuthService) {
    self.auth = auth
  }

  private static let columns =
    "surface,reading,meaning,source_title,source_artist,source_line,source_line_translation,level,due_at,created_at,updated_at"

  /// Every flashcard for the signed-in user (RLS filters to them), newest edit
  /// first, carrying `updated_at` so the cache reconciles last-writer-wins.
  func fetchAll() async throws -> [Flashcard] {
    let rows: [FlashcardRow] = try await auth.client
      .from("flashcards")
      .select(Self.columns)
      .order("updated_at", ascending: false)
      .execute()
      .value
    return rows.map(\.asCard)
  }

  /// Insert (or update) one card. `user_id` must be sent explicitly — the column
  /// has no default — and comes from the session; the conflict target is the
  /// `(user_id, surface)` unique constraint, so a re-save / re-grade is idempotent.
  func upsert(_ card: Flashcard) async throws {
    let userID = try await auth.client.auth.session.user.id
    let row = FlashcardInsert(card: card, userID: userID.uuidString.lowercased())
    try await auth.client
      .from("flashcards")
      .upsert(row, onConflict: "user_id,surface")
      .execute()
  }

  /// Remove one card. The `user_id` filter is belt-and-braces — RLS already
  /// scopes the delete to `auth.uid()` — and matches the `(user_id, surface)` row
  /// the upsert wrote. This `DELETE` is what lets the web client observe removal.
  func delete(surface: String) async throws {
    let userID = try await auth.client.auth.session.user.id
    try await auth.client
      .from("flashcards")
      .delete()
      .eq("user_id", value: userID.uuidString.lowercased())
      .eq("surface", value: surface)
      .execute()
  }
}

/// The `flashcards` columns the cache mirror needs. The timestamptz columns
/// decode into `Date` via the Supabase client's decoder, the same as `OverrideRow`.
private struct FlashcardRow: Decodable {
  let surface: String
  let reading: String
  // jsonb gloss maps keyed by translation target (see migration 011); null on
  // a never-glossed row, normalized to an empty map in `asCard`.
  let meaning: [String: String]?
  let sourceTitle: String?
  let sourceArtist: String?
  let sourceLine: String?
  let sourceLineTranslation: [String: String]?
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
    case dueAt = "due_at"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }

  var asCard: Flashcard {
    Flashcard(
      surface: surface,
      reading: reading,
      meaning: meaning ?? [:],
      sourceTitle: sourceTitle,
      sourceArtist: sourceArtist,
      sourceLine: sourceLine,
      sourceLineTranslation: sourceLineTranslation ?? [:],
      level: level,
      dueAt: dueAt,
      createdAt: createdAt,
      updatedAt: updatedAt
    )
  }
}

/// The upsert payload. Timestamps are encoded as explicit ISO-8601 strings
/// rather than relying on the client's `Date` encoding: the schedule columns
/// (`due_at`) and `updated_at` are sent on every write (grading changes them),
/// and a fixed ISO-8601 representation is what Postgres `timestamptz` accepts
/// unambiguously.
private struct FlashcardInsert: Encodable {
  let userID: String
  let surface: String
  let reading: String
  let meaning: [String: String]
  let sourceTitle: String?
  let sourceArtist: String?
  let sourceLine: String?
  let sourceLineTranslation: [String: String]
  let level: Int
  let dueAt: String
  let createdAt: String
  let updatedAt: String

  init(card: Flashcard, userID: String) {
    self.userID = userID
    surface = card.surface
    reading = card.reading
    meaning = card.meaning
    sourceTitle = card.sourceTitle
    sourceArtist = card.sourceArtist
    sourceLine = card.sourceLine
    sourceLineTranslation = card.sourceLineTranslation
    level = card.level
    dueAt = Self.iso.string(from: card.dueAt)
    createdAt = Self.iso.string(from: card.createdAt)
    updatedAt = Self.iso.string(from: card.updatedAt)
  }

  private static let iso: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  enum CodingKeys: String, CodingKey {
    case userID = "user_id"
    case surface, reading, meaning, level
    case sourceTitle = "source_title"
    case sourceArtist = "source_artist"
    case sourceLine = "source_line"
    case sourceLineTranslation = "source_line_translation"
    case dueAt = "due_at"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }
}
