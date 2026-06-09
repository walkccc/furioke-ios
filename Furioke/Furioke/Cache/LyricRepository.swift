import Foundation

/// Read-through lyric-body cache. Wraps `LyricsService` (the `/api/lyrics`
/// client) and `OfflineCache` (`LyricBodyEntity`), keyed by `MusicTrack.id`, and
/// resolves the online/offline × hit/miss/stale matrix through `ReadThroughCache`.
/// The caller (`NowPlayingState`) runs each emitted body through the furigana
/// annotator.
@MainActor
final class LyricRepository {
  private let service: LyricsService
  private let cache: OfflineCache
  private let network: NetworkMonitor

  init(service: LyricsService, cache: OfflineCache, network: NetworkMonitor) {
    self.service = service
    self.cache = cache
    self.network = network
  }

  func load(for track: MusicTrack) -> AsyncStream<CacheLoad<LyricFetchResult>> {
    let cached = cache.lyricBody(forSongID: track.id).map {
      (value: LyricFetchResult(body: $0.bodyText, lrclibID: $0.lrclibID), fetchedAt: $0.fetchedAt)
    }
    let service = service
    let cache = cache
    let songID = track.id
    return ReadThroughCache.load(
      isOnline: network.isOnline,
      cached: cached,
      ttl: OfflineCache.ttl,
      // Lyrics for a track are effectively immutable, so a fresh cache hit renders
      // with NO `/api/lyrics` call. Only a miss or a stale (TTL-expired) entry
      // fetches — playing a cached song offline *or* online stays network-free.
      revalidateFreshHits: false,
      fetch: { try await service.fetchBody(for: track) },
      store: { result in
        cache.upsertLyricBody(songID: songID, lrclibID: result.lrclibID, body: result.body)
      }
    )
  }
}
