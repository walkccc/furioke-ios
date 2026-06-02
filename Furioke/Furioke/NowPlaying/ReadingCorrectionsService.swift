import Foundation
import Supabase

/// Writes the user's personal reading overrides directly to the Supabase
/// `reading_overrides` table — the same table the web app reads. RLS scopes
/// every row to `auth.uid()`, and the `(user_id, surface)` unique constraint makes
/// the write an idempotent upsert, mirroring `SavedSongsService`.
///
/// Contract note: the table columns are `user_id`, `surface`, `reading`, mirroring
/// `OverrideEntity`; the conflict target is the `(user_id, surface)` unique
/// constraint. The table itself is owned by the backend repo.
struct ReadingCorrectionsService {
  private let auth: AuthService

  init(auth: AuthService) {
    self.auth = auth
  }

  /// Every reading override for the signed-in user (RLS filters to them), carrying
  /// `updated_at` so the cache can reconcile last-writer-wins against local edits.
  /// This is the only server→cache pull for overrides; without it a row written on
  /// another device (or a reinstall) never reaches this device.
  func fetchAll() async throws -> [RemoteReadingOverride] {
    let rows: [OverrideRow] = try await auth.client
      .from("reading_overrides")
      .select("surface,reading,updated_at")
      .execute()
      .value
    return rows.map {
      RemoteReadingOverride(surface: $0.surface, reading: $0.reading, updatedAt: $0.updatedAt)
    }
  }

  /// Insert (or update) the signed-in user's override for `surface`. `user_id` must
  /// be sent explicitly — the column has no default — and comes from the session.
  func upsert(surface: String, reading: String) async throws {
    let userID = try await auth.client.auth.session.user.id
    let row = OverrideInsert(
      userID: userID.uuidString.lowercased(),
      surface: surface,
      reading: reading
    )
    try await auth.client
      .from("reading_overrides")
      .upsert(row, onConflict: "user_id,surface")
      .execute()
  }

  /// Delete the signed-in user's override for `surface`. The `user_id` filter is
  /// belt-and-braces — RLS already scopes every row to `auth.uid()` — and matches
  /// the `(user_id, surface)` row the upsert wrote. This `DELETE` is what lets the
  /// web client observe the removal.
  func delete(surface: String) async throws {
    let userID = try await auth.client.auth.session.user.id
    try await auth.client
      .from("reading_overrides")
      .delete()
      .eq("user_id", value: userID.uuidString.lowercased())
      .eq("surface", value: surface)
      .execute()
  }
}

/// A reading override crossing the Supabase → cache boundary, mirroring one
/// `reading_overrides` row. `updatedAt` is the reconcile tiebreaker.
nonisolated struct RemoteReadingOverride: Equatable {
  let surface: String
  let reading: String
  let updatedAt: Date
}

/// The subset of `reading_overrides` columns the cache mirror needs. `updated_at`
/// decodes via the Supabase client's timestamptz-aware decoder.
private struct OverrideRow: Decodable {
  let surface: String
  let reading: String
  let updatedAt: Date

  enum CodingKeys: String, CodingKey {
    case surface, reading
    case updatedAt = "updated_at"
  }
}

private struct OverrideInsert: Encodable {
  let userID: String
  let surface: String
  let reading: String

  enum CodingKeys: String, CodingKey {
    case userID = "user_id"
    case surface
    case reading
  }
}
