import Foundation
import Observation

/// The Library slice observable: the seam Search and NowPlaying use to
/// save a track and to ask whether it's already saved, and the launch/activation
/// sync that reconciles the local `SongEntity` mirror with the server's `songs`
/// table. The `LibraryView` list itself reads SwiftData via `@Query`, so it
/// updates automatically when a save writes through the cache; `savedIDs` exists
/// only to drive the Save/​Saved button state in views that aren't query-backed.
@Observable
@MainActor
final class LibraryState {
  /// Track ids of saved songs, mirrored in memory for O(1), reactive button state.
  private(set) var savedIDs: Set<String> = []

  private let cache: OfflineCache
  private let service: SavedSongsService
  private let network: NetworkMonitor

  init(cache: OfflineCache, service: SavedSongsService, network: NetworkMonitor) {
    self.cache = cache
    self.service = service
    self.network = network
    savedIDs = cache.savedSongIDs()
  }

  func isSaved(_ track: MusicTrack) -> Bool {
    savedIDs.contains(track.id)
  }

  /// Reconcile the local mirror with the server. No-op while offline — the
  /// Library renders from the cache and must not blank or error.
  func sync() async {
    guard network.isOnline else { return }
    guard let songs = try? await service.fetchAll() else { return }
    cache.reconcileSongs(songs)
    savedIDs = cache.savedSongIDs()
  }

  /// Save a track: upsert into `songs`, then mirror into the local cache so the
  /// Library list reflects it immediately. Already-saved is a
  /// no-op. Returns whether the song is saved after the call.
  @discardableResult
  func save(_ track: MusicTrack) async -> Bool {
    guard !isSaved(track) else { return true }
    let song = SavedSong(
      provider: track.provider.rawValue,
      providerTrackID: track.providerTrackID,
      title: track.title,
      artist: track.artists.isEmpty ? nil : track.artists.joined(separator: ", "),
      album: track.album,
      durationMs: track.durationMs,
      artworkURL: track.artworkURL?.absoluteString,
      savedAt: .now
    )
    do {
      try await service.upsert(song)
      cache.upsertSong(song)
      savedIDs.insert(song.id)
      return true
    } catch {
      return false
    }
  }

  /// Unsave a track: delete from `songs`, then drop the local mirror so the Library
  /// list and Save/​Saved button state update immediately. Not-saved is a no-op.
  /// Returns whether the song is unsaved (absent) after the call.
  @discardableResult
  func remove(_ track: MusicTrack) async -> Bool {
    guard isSaved(track) else { return true }
    do {
      try await service.delete(
        provider: track.provider.rawValue,
        providerTrackID: track.providerTrackID
      )
      cache.deleteSong(id: track.id)
      savedIDs.remove(track.id)
      return true
    } catch {
      return false
    }
  }
}
