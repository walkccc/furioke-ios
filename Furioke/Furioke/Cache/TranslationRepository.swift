import Foundation

/// The cached translation payload: the raw translated body (one line per lyric
/// line) plus the model version it was generated with. `Equatable` so an unchanged
/// revalidation skips a re-render.
nonisolated struct TranslationPayload: Equatable {
  let bodyJson: String
  let modelVersion: String
}

/// Read-through translation cache, keyed by `(songID, language)`
/// against `TranslationEntity`. Reuses `ReadThroughCache`, but with
/// `revalidateFreshHits: false`: a cached translation renders without any
/// `/api/translate` call (translation spends a per-user model quota). A cache
/// miss while online calls `/api/translate` with the lyric
/// body and writes the result through; offline with no cache yields
/// `.unavailableOffline`.
@MainActor
final class TranslationRepository {
  private let service: TranslationService
  private let cache: OfflineCache
  private let network: NetworkMonitor

  init(service: TranslationService, cache: OfflineCache, network: NetworkMonitor) {
    self.service = service
    self.cache = cache
    self.network = network
  }

  /// - Parameters:
  ///   - songID: the track identity (`provider:providerTrackID`), the cache key.
  ///   - language: the target language (the cache key + the `/api/translate` target).
  ///   - sourceText: the lyric body to translate on a cache miss (one line per
  ///     lyric line, so the response aligns to the rendered lines by index).
  func load(songID: String, language: String,
            sourceText: String) -> AsyncStream<CacheLoad<TranslationPayload>>
  {
    let cached = cache.translation(forSongID: songID, language: language).map {
      (
        value: TranslationPayload(bodyJson: $0.bodyJson, modelVersion: $0.modelVersion),
        fetchedAt: $0.generatedAt
      )
    }
    let service = self.service
    let cache = self.cache
    let modelVersion = TranslationService.modelVersion
    return ReadThroughCache.load(
      isOnline: network.isOnline,
      cached: cached,
      ttl: OfflineCache.ttl,
      revalidateFreshHits: false,
      fetch: {
        guard let translated = try await service.translate(text: sourceText, target: language)
        else {
          return nil
        }
        return TranslationPayload(bodyJson: translated, modelVersion: modelVersion)
      },
      store: { payload in
        cache.upsertTranslation(
          songID: songID,
          language: language,
          bodyJson: payload.bodyJson,
          modelVersion: payload.modelVersion
        )
      }
    )
  }
}
