import Foundation

/// One outcome of a read-through cache load. `.value` may be delivered **twice**
/// on the online-fresh path: the cached payload immediately, then a second time
/// if background revalidation returns a changed payload — the seam that lets the
/// surface render instantly and re-render on a server update.
enum CacheLoad<Payload: Equatable & Sendable>: Equatable {
  case value(Payload)
  /// Online, no cache, and the server has no entry.
  case notFound
  /// Offline with nothing cached — render a quiet unavailable state, no retry.
  case unavailableOffline
  /// Online fetch failed with nothing cached to fall back to.
  case failed
}

/// The shared read-through state machine for the offline cache, used by both the
/// lyric-body and translation repositories. The branching is exactly:
///
/// - **online + fresh hit** → serve cache now, revalidate in the background,
///   re-emit only if the payload changed;
/// - **online + miss/stale** → fetch + write through; on a network error fall
///   back to a stale cached copy if one exists, else `.failed`; if the server has
///   no entry, `.notFound` (or the stale copy, beating a blank screen);
/// - **offline + hit** → serve cache, no network attempt;
/// - **offline + miss** → `.unavailableOffline`, no retry, no toast.
enum ReadThroughCache {
  /// - Parameter revalidateFreshHits: when `true`, a fresh cache hit is served
  ///   immediately and then revalidated in the background. When `false` (both
  ///   lyrics and translations), a fresh hit makes **no** network call at all — a
  ///   cached lyric/translation renders without an `/api/lyrics` or
  ///   `/api/translate` request (and, for translations, without spending the
  ///   per-user model quota). Only a miss or a TTL-stale entry fetches.
  @MainActor
  static func load<Payload: Equatable & Sendable>(
    isOnline: Bool,
    cached: (value: Payload, fetchedAt: Date)?,
    ttl: TimeInterval,
    revalidateFreshHits: Bool = true,
    fetch: @escaping @Sendable () async throws -> Payload?,
    store: @escaping @MainActor (Payload) -> Void
  ) -> AsyncStream<CacheLoad<Payload>> {
    AsyncStream { continuation in
      let task = Task { @MainActor in
        let stale = cached.map { Date().timeIntervalSince($0.fetchedAt) > ttl } ?? false

        guard isOnline else {
          // Offline: cache is the only source. Stale-but-present still wins.
          continuation.yield(cached.map { .value($0.value) } ?? .unavailableOffline)
          continuation.finish()
          return
        }

        if let cached, !stale {
          // Fresh hit: serve immediately.
          continuation.yield(.value(cached.value))
          if revalidateFreshHits {
            // Revalidate without blocking the UI; re-emit only on a real change.
            do {
              if let fresh = try await fetch(), fresh != cached.value {
                store(fresh)
                continuation.yield(.value(fresh))
              }
            } catch {
              // Revalidation failure leaves the already-served cache in place.
            }
          }
        } else {
          // Miss or stale: the network is the source of truth.
          do {
            if let fresh = try await fetch() {
              store(fresh)
              continuation.yield(.value(fresh))
            } else if let cached {
              // Server has nothing now, but a stale copy beats a blank screen.
              continuation.yield(.value(cached.value))
            } else {
              continuation.yield(.notFound)
            }
          } catch {
            continuation.yield(cached.map { .value($0.value) } ?? .failed)
          }
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}
