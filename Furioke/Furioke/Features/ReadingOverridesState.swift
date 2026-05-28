import Foundation
import Observation
import SwiftUI

/// Backs the Reading Overrides management screen: reads the signed-in user's
/// override rows from the cache and drives edit / delete, with the same
/// optimistic-local-then-upload discipline as the playback editor
/// (`NowPlayingState.recordOverride`). It deliberately does **not** reach into
/// `NowPlayingState` — edits and deletes re-annotate lyrics on the next song load,
/// not live (`CorrectionMap` is rebuilt on `loadLyrics`), so this screen stays
/// self-contained. The reconnect flush that drains offline tombstones lives in
/// `NowPlayingState.syncPendingOverrides`, the app's single reconnect seam.
@Observable
@MainActor
final class ReadingOverridesState {
  /// The user's overrides for display, newest list rebuilt by `reload`.
  /// `.pendingDelete` tombstones are already excluded by the cache accessor.
  private(set) var rows: [ReadingOverride] = []

  private let cache: OfflineCache
  private let corrections: ReadingCorrectionsService
  private let auth: AuthService
  private let network: NetworkMonitor

  init(
    cache: OfflineCache,
    corrections: ReadingCorrectionsService,
    auth: AuthService,
    network: NetworkMonitor
  ) {
    self.cache = cache
    self.corrections = corrections
    self.auth = auth
    self.network = network
  }

  /// Whether a user is signed in. Overrides are per-user, so a signed-out visitor
  /// sees a sign-in prompt instead of a list.
  var isSignedIn: Bool {
    currentUserID != nil
  }

  /// Refetch the list from the cache. Called on appear and after every mutation.
  func reload() {
    rows = currentUserID.map(cache.overrideRows(forUserID:)) ?? []
  }

  /// Pull the server's overrides into the cache, then reload. Mirrors
  /// `LibraryState.sync`: no-op while offline (the list renders from the cache and
  /// must not blank). Flushing queued local writes is owned by
  /// `NowPlayingState.syncPendingOverrides`, the single reconnect seam — here we
  /// only need the download so a row written elsewhere (or before a reinstall)
  /// appears the moment this screen opens.
  func sync() async {
    guard network.isOnline, let userID = currentUserID else { return }
    guard let serverRows = try? await corrections.fetchAll() else { return }
    cache.reconcileOverrides(userID: userID, serverRows: serverRows)
    reload()
  }

  /// Change an override's reading. Optimistic local write first (so a later reload
  /// shows it), then upload when online — mirroring the playback edit path. The new
  /// reading takes effect the next time a song containing the kanji loads.
  func updateReading(surface: String, reading: String) async {
    guard let userID = currentUserID else { return }
    let reading = reading.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !reading.isEmpty else { return }

    cache.upsertOverride(userID: userID, surface: surface, reading: reading, source: .local)
    reload()

    guard network.isOnline else { return }
    do {
      try await corrections.upsert(surface: surface, reading: reading)
      cache.markOverrideSynced(userID: userID, surface: surface)
      reload()
    } catch {
      // Stay `.local`; the reconnect flush retries the upload.
    }
  }

  /// Delete an override. Online + already synced: issue the Supabase `DELETE`, then
  /// drop the local row (tombstone it on failure for the reconnect flush). Otherwise
  /// (`.local` never-uploaded, or synced-but-offline) hand off to `deleteOverride`,
  /// which drops a `.local` row outright and tombstones a `.synced` one.
  func delete(_ override: ReadingOverride) async {
    guard let userID = currentUserID else { return }
    let surface = override.surface

    if !override.isPendingSync, network.isOnline {
      do {
        try await corrections.delete(surface: surface)
        cache.removeOverride(userID: userID, surface: surface)
      } catch {
        cache.deleteOverride(userID: userID, surface: surface)
      }
    } else {
      cache.deleteOverride(userID: userID, surface: surface)
    }
    reload()
  }

  /// The signed-in user's id in the lowercased-UUID form used for `OverrideEntity`
  /// rows; nil when signed out. Mirrors `NowPlayingState.currentUserID`.
  private var currentUserID: String? {
    if case let .signedIn(userID) = auth.state {
      return userID.uuidString.lowercased()
    }
    return nil
  }
}
